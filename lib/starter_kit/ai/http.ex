defmodule StarterKit.AI.HTTP do
  @moduledoc false
  # The only place that talks HTTP to AI providers. Tests swap it via
  # `config :starter_kit, StarterKit.AI, http: StarterKit.AI.FakeHTTP`.

  @callback post(url :: String.t(), headers :: list(), body :: map(), opts :: keyword()) ::
              {:ok, map()} | {:error, term()}

  def post(url, headers, body, opts) do
    case Req.post(url,
           headers: headers,
           json: body,
           receive_timeout: opts[:timeout] || 60_000,
           retry: :transient
         ) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 -> {:ok, body}
      {:ok, %Req.Response{status: status, body: body}} -> {:error, {:http, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end
end
