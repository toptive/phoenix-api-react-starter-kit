defmodule StarterKitWeb.ConditionalGet do
  @moduledoc "Shared public revalidation headers and conditional GET handling."
  import Plug.Conn

  def render(conn, etag, render) do
    conn =
      conn |> put_resp_header("etag", etag) |> put_resp_header("cache-control", "public, no-cache")

    matches =
      conn
      |> get_req_header("if-none-match")
      |> Enum.flat_map(&String.split(&1, ","))
      |> Enum.any?(&(String.replace_prefix(String.trim(&1), "W/", "") in [etag, "*"]))

    if matches, do: send_resp(conn, 304, ""), else: render.(conn)
  end
end
