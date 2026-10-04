defmodule StarterKitWeb.Api.V1.EventController do
  @moduledoc "Client-side analytics events (only those the catalogue marks as client events)."
  use StarterKitWeb, :controller

  alias StarterKit.Analytics

  plug StarterKitWeb.Plugs.RateLimit, bucket: "events", limit: 120, period: 60_000

  def create(conn, %{"event" => %{"name" => name} = event}) do
    conn = skip_authorization(conn)
    Analytics.track(name, scope(conn), Map.get(event, "properties", %{}), client: true)
    conn |> put_status(202) |> render_data(%{accepted: true})
  end

  def create(conn, _params), do: conn |> skip_authorization() |> render_error(400, :bad_request)
end
