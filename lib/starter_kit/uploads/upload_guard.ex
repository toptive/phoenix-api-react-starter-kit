defmodule StarterKit.Uploads.UploadGuard do
  @moduledoc """
  Decides what may be uploaded: an allow-list of content types and a size cap per
  `kind`, and a byte sniff of the stored object (the browser-declared type is never
  trusted alone). SVG is never allowed (it can carry scripts).
  """

  @kinds %{
    "image" => %{types: ~w(image/jpeg image/png image/webp image/gif), max_bytes: 10_000_000},
    "document" => %{types: ~w(application/pdf image/jpeg image/png), max_bytes: 20_000_000},
    "avatar" => %{types: ~w(image/jpeg image/png image/webp), max_bytes: 2_000_000}
  }

  @doc "Upload kinds and their rules."
  def kinds, do: @kinds

  @doc "Checks the declared type and size before we sign an upload URL."
  def check(kind, content_type, byte_size) do
    case Map.get(@kinds, kind) do
      nil ->
        {:error, :unknown_kind}

      %{types: types, max_bytes: max} ->
        cond do
          content_type not in types -> {:error, :content_type_not_allowed}
          not is_integer(byte_size) or byte_size <= 0 -> {:error, :invalid_size}
          byte_size > max -> {:error, :too_large}
          true -> :ok
        end
    end
  end

  @doc "Detects the real type from the first bytes of the stored file."
  def sniff(<<0xFF, 0xD8, 0xFF, _::binary>>), do: "image/jpeg"
  def sniff(<<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, _::binary>>), do: "image/png"
  def sniff(<<"GIF8", _::binary>>), do: "image/gif"
  def sniff(<<"RIFF", _::binary-size(4), "WEBP", _::binary>>), do: "image/webp"
  def sniff(<<"%PDF-", _::binary>>), do: "application/pdf"
  def sniff(_), do: "application/octet-stream"

  @doc "True when the sniffed bytes match an allowed type for `kind`."
  def bytes_allowed?(kind, head) do
    case Map.get(@kinds, kind) do
      %{types: types} -> sniff(head) in types
      nil -> false
    end
  end

  @doc "A safe object name: lowercase ascii, dashes, keeps the extension."
  def safe_filename(filename) do
    ext = filename |> Path.extname() |> String.downcase() |> String.replace(~r/[^.a-z0-9]/, "")

    base =
      filename
      |> Path.rootname()
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")
      |> String.slice(0, 60)

    if(base == "", do: "file", else: base) <> ext
  end
end
