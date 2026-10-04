defmodule StarterKit.Uploads do
  @moduledoc """
  Direct uploads to S3-compatible storage (DigitalOcean Spaces, R2, S3, MinIO).

  1. The browser asks `POST /api/v1/direct-uploads` → `presign/2` checks the request
     with `UploadGuard` and returns a short-lived PUT URL + the object key.
  2. The browser PUTs the file straight to storage (the app never proxies bytes).
  3. The form submits the key; the owning context calls `verify/2`, which sniffs the
     stored bytes and size before the key is saved.

  Objects are private. Read them through `url/2` (presigned GET, 5 minutes).
  Config: `S3_BUCKET`, `S3_ENDPOINT`, `S3_REGION`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY`.
  """

  use Boundary, top_level?: true, deps: [StarterKit.Accounts], exports: []

  alias StarterKit.Accounts.Scope
  alias StarterKit.Uploads.UploadGuard

  @put_expiry 600
  @get_expiry 300

  @doc "Upload kinds the frontend may request."
  def kinds, do: Map.keys(UploadGuard.kinds())

  @doc """
  Signs an upload for `owner_prefix` (usually the organization id).
  `params`: `filename`, `content_type`, `byte_size`, `kind`.
  Returns `{:ok, %{url, key, method, headers}}` or `{:error, reason}`.
  """
  def presign(%Scope{} = scope, params),
    do: presign(Scope.organization_id(scope), params)

  def presign(owner_prefix, %{
        "filename" => filename,
        "content_type" => type,
        "byte_size" => size,
        "kind" => kind
      })
      when is_binary(filename) and is_binary(type) and is_binary(kind) do
    with :ok <- UploadGuard.check(kind, type, size),
         {:ok, bucket} <- bucket() do
      key = "uploads/#{owner_prefix}/#{Ecto.UUID.generate()}/#{UploadGuard.safe_filename(filename)}"

      {:ok, url} =
        ExAws.Config.new(:s3)
        |> ExAws.S3.presigned_url(:put, bucket, key,
          expires_in: @put_expiry,
          headers: [{"content-type", type}]
        )

      {:ok,
       %{
         url: url,
         key: key,
         method: "PUT",
         headers: %{"content-type" => type}
       }}
    end
  rescue
    ArgumentError -> {:error, :invalid_size}
  end

  def presign(_owner_prefix, _params), do: {:error, :invalid_request}

  @doc "Checks a stored object: it exists, fits the size cap, and its bytes match `kind`."
  def verify(key, kind) do
    with {:ok, bucket} <- bucket(),
         {:ok, %{headers: headers}} <- bucket |> ExAws.S3.head_object(key) |> storage_request(),
         {size, ""} <- Integer.parse(header(headers, "content-length")),
         true <- size > 0,
         :ok <- size_ok(kind, size),
         {:ok, %{body: head}} <-
           bucket |> ExAws.S3.get_object(key, range: "bytes=0-15") |> storage_request(),
         true <- UploadGuard.bytes_allowed?(kind, head) do
      :ok
    else
      _ -> {:error, :upload_incomplete}
    end
  end

  @doc "Verifies ownership as well as stored bytes before a tenant context saves a key."
  def verify(%Scope{} = scope, key, kind) when is_binary(key) do
    prefix = "uploads/#{Scope.organization_id(scope)}/"

    if String.starts_with?(key, prefix) and not String.contains?(key, ["..", "\\"]),
      do: verify(key, kind),
      else: {:error, :upload_incomplete}
  end

  def verify(_scope, _key, _kind), do: {:error, :upload_incomplete}

  defp storage_request(operation) do
    options = Application.get_env(:starter_kit, __MODULE__, [])[:request_options] || []
    ExAws.request(operation, options)
  end

  @doc "A presigned GET URL for a private object."
  def url(key, opts \\ []) do
    with {:ok, bucket} <- bucket() do
      ExAws.Config.new(:s3)
      |> ExAws.S3.presigned_url(:get, bucket, key, expires_in: opts[:expires_in] || @get_expiry)
    end
  end

  defp size_ok(kind, size) do
    case UploadGuard.kinds() do
      %{^kind => %{max_bytes: max}} when size <= max -> :ok
      _ -> {:error, :too_large}
    end
  end

  defp header(headers, name) do
    Enum.find_value(headers, "0", fn {k, v} -> if String.downcase(k) == name, do: v end)
  end

  defp bucket do
    case Application.get_env(:starter_kit, __MODULE__, [])[:bucket] do
      bucket when is_binary(bucket) and bucket != "" -> {:ok, bucket}
      _ -> {:error, :not_configured}
    end
  end
end
