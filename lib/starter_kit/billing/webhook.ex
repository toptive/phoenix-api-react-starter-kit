defmodule StarterKit.Billing.Webhook do
  @moduledoc false
  # Stripe webhook signatures (https://docs.stripe.com/webhooks#verify-manually).
  #
  # Header: `Stripe-Signature: t=<unix>,v1=<hex>[,v1=<hex>…]`. The signed payload is
  # "<t>.<raw body>", HMAC-SHA256 with the endpoint secret. The RAW bytes are required:
  # a re-encoded JSON body never matches. A timestamp older (or newer) than the
  # tolerance is refused, so a captured request cannot be replayed later.

  @tolerance_seconds 300

  @doc false
  def verify(raw_body, header, secret, now \\ System.system_time(:second))

  def verify(raw_body, header, secret, now)
      when is_binary(raw_body) and is_binary(header) and is_binary(secret) do
    with {:ok, timestamp, signatures} <- parse(header),
         :ok <- fresh(timestamp, now) do
      match(signatures, expected(secret, timestamp, raw_body))
    end
  end

  def verify(_raw_body, _header, _secret, _now), do: {:error, :invalid_signature}

  @doc false
  def sign(raw_body, secret, timestamp \\ System.system_time(:second)),
    do: "t=#{timestamp},v1=#{expected(secret, timestamp, raw_body)}"

  defp parse(header) do
    pairs =
      for part <- String.split(header, ","),
          [key, value] <- [String.split(String.trim(part), "=", parts: 2)],
          do: {key, value}

    with {"t", t} <- List.keyfind(pairs, "t", 0),
         {timestamp, ""} <- Integer.parse(t),
         [_ | _] = signatures <- for({"v1", sig} <- pairs, do: sig) do
      {:ok, timestamp, signatures}
    else
      _ -> {:error, :invalid_signature}
    end
  end

  defp fresh(timestamp, now) when abs(now - timestamp) <= @tolerance_seconds, do: :ok
  defp fresh(_timestamp, _now), do: {:error, :stale_signature}

  defp match(signatures, expected) do
    if Enum.any?(signatures, &Plug.Crypto.secure_compare(&1, expected)),
      do: :ok,
      else: {:error, :invalid_signature}
  end

  defp expected(secret, timestamp, raw_body),
    do:
      :hmac
      |> :crypto.mac(:sha256, secret, "#{timestamp}.#{raw_body}")
      |> Base.encode16(case: :lower)
end
