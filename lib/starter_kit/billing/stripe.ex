defmodule StarterKit.Billing.Stripe do
  @moduledoc false
  # The only place that talks HTTP to Stripe (called by StarterKit.Billing only).
  #
  # - The API version is pinned: a Stripe dashboard upgrade never changes our payloads.
  # - No retries and no redirects: a payment call either answers or fails visibly;
  #   idempotency keys make a repeated click safe instead.
  # - Errors keep only Stripe's `type`, `code` and `param`. Stripe messages can carry
  #   customer data, so they are never logged or returned.
  #
  # Tests swap the transport with
  # `config :starter_kit, StarterKit.Billing, req_options: [plug: {Req.Test, StarterKit.Billing.Stripe}]`.

  require Logger

  @api_version "2025-09-30.clover"

  @doc false
  def api_version, do: @api_version

  @doc false
  def get(path, secret_key), do: request(:get, path, nil, secret_key, nil)

  @doc false
  def post(path, form, secret_key, idempotency_key),
    do: request(:post, path, form, secret_key, idempotency_key)

  defp request(method, path, form, secret_key, idempotency_key) do
    headers =
      [{"stripe-version", @api_version}] ++
        if(idempotency_key, do: [{"idempotency-key", idempotency_key}], else: [])

    [
      method: method,
      base_url: "https://api.stripe.com/v1/",
      url: path,
      auth: {:bearer, secret_key},
      headers: headers,
      retry: false,
      redirect: false,
      receive_timeout: 15_000
    ]
    |> then(&if(form, do: Keyword.put(&1, :form, form), else: &1))
    |> Keyword.merge(Application.get_env(:starter_kit, StarterKit.Billing, [])[:req_options] || [])
    |> Req.request()
    |> case do
      {:ok, %Req.Response{status: status, body: %{} = body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        error = (is_map(body) && body["error"]) || %{}
        details = Map.take(error, ["type", "code", "param"])
        Logger.warning("stripe #{method} #{path} failed: #{status} #{inspect(details)}")
        {:error, {:stripe, status, details}}

      {:error, exception} ->
        Logger.warning("stripe #{method} #{path} unreachable: #{inspect(exception.__struct__)}")
        {:error, :stripe_unreachable}
    end
  end
end
