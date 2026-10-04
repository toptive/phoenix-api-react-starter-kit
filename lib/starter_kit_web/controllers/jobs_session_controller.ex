defmodule StarterKitWeb.JobsSessionController do
  @moduledoc "Browser handoff for the jobs dashboard."
  use StarterKitWeb, :controller

  def show(conn, params) do
    conn =
      conn
      |> skip_authorization()
      |> put_resp_header("cache-control", "private, no-store")
      |> put_resp_header("referrer-policy", "no-referrer")

    case params["ticket"] do
      ticket when is_binary(ticket) -> StarterKitWeb.JobsAccess.exchange(conn, ticket)
      _ -> render_error(conn, 404, :not_found)
    end
  end
end
