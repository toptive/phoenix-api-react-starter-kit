defmodule StarterKitWeb.HealthController do
  @moduledoc "kamal-proxy health check: cheap, no session."
  use StarterKitWeb, :controller

  def show(conn, _params) do
    conn = skip_authorization(conn) |> put_resp_header("cache-control", "no-store")

    case StarterKit.Health.check() do
      :ok -> text(conn, "ok")
      {:error, _} -> conn |> put_status(503) |> text("database unavailable")
    end
  end
end
