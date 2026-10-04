defmodule StarterKitWeb.Plugs.Cors do
  @moduledoc "API CORS with an explicit origin allow-list and bounded preflight headers."
  @behaviour Plug
  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%{path_info: ["api", "v1" | _]} = conn, _opts) do
    conn = merge_vary(conn)
    origins = Application.get_env(:starter_kit, :cors_origins, [])

    case get_req_header(conn, "origin") do
      [origin] ->
        if origin in origins do
          conn
          |> put_resp_header("access-control-allow-origin", origin)
          |> put_resp_header("access-control-expose-headers", "ETag, Retry-After")
          |> preflight()
        else
          conn
        end

      _ ->
        conn
    end
  end

  def call(conn, _opts), do: conn

  defp preflight(%{method: "OPTIONS"} = conn) do
    conn
    |> put_resp_header("access-control-allow-methods", "GET, POST, PUT, DELETE, OPTIONS")
    |> put_resp_header(
      "access-control-allow-headers",
      "Authorization, Content-Type, Accept-Language, If-None-Match"
    )
    |> put_resp_header("access-control-max-age", "600")
    |> send_resp(204, "")
    |> halt()
  end

  defp preflight(conn), do: conn

  defp merge_vary(conn) do
    vary = Enum.join(get_resp_header(conn, "vary") ++ ["Origin"], ", ")
    put_resp_header(conn, "vary", vary)
  end
end
