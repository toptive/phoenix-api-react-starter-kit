defmodule StarterKitWeb.Settings.AppearanceController do
  @moduledoc "Light, dark or system theme (stored in the browser)."
  use StarterKitWeb, :controller
  use Typelizer.InertiaPage

  page "settings/appearance/edit", props: []

  def edit(conn, _params) do
    conn |> authorize!(:edit, scope(conn).user) |> render_inertia("settings/appearance/edit")
  end
end
