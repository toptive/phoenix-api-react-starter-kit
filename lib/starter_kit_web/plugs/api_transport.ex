defmodule StarterKitWeb.Plugs.ApiTransport do
  @moduledoc "JSON transport errors and method handling, including form-encoded RFC 8058 opt-out."
  @behaviour Plug
  import Plug.Conn
  alias StarterKitWeb.{Responses, Router}

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%{path_info: ["api", "v1" | _]} = conn, _opts) do
    cond do
      wrong_method?(conn) -> conn |> Responses.render_error(405, :bad_request) |> halt()
      unsupported_type?(conn) -> conn |> Responses.render_error(415, :bad_request) |> halt()
      true -> parse(conn)
    end
  end

  def call(conn, _opts), do: parse(conn)

  defp unsupported_type?(conn) do
    case get_req_header(conn, "content-type") do
      [] ->
        false

      [type] ->
        not String.starts_with?(type, "application/json") and
          not (String.ends_with?(conn.request_path, "/opt-out") and
                 String.starts_with?(conn.request_path, "/api/v1/email-subscriptions/") and
                 String.starts_with?(type, "application/x-www-form-urlencoded"))
    end
  end

  defp wrong_method?(conn) do
    conn.method not in ["GET", "POST", "PUT", "DELETE", "HEAD", "OPTIONS"] or
      (Phoenix.Router.route_info(Router, conn.method, conn.request_path, conn.host) == :error and
         Enum.any?(["GET", "POST", "PUT", "DELETE"], fn method ->
           Phoenix.Router.route_info(Router, method, conn.request_path, conn.host) != :error
         end))
  end

  defp parse(conn) do
    opts =
      Plug.Parsers.init(
        parsers: [:urlencoded, :multipart, :json],
        pass: ["*/*"],
        length: 8_000_000,
        json_decoder: Phoenix.json_library(),
        body_reader: {StarterKitWeb.Plugs.RawBody, :read_body, []}
      )

    Plug.Parsers.call(conn, opts)
  rescue
    Plug.Parsers.ParseError ->
      conn |> Responses.render_error(400, :invalid_json) |> halt()
  end
end
