defmodule StarterKitWeb.DashboardController do
  @moduledoc """
  Home of the signed-in app. Products replace the page content. A manager of an
  organization that has not finished onboarding goes to the onboarding steps first.
  """
  use StarterKitWeb, :controller
  use Typelizer.InertiaPage

  alias StarterKit.Organizations
  alias StarterKit.Organizations.Organization

  page "dashboard/show", props: []

  def show(conn, _params) do
    conn = authorize!(conn, :show, scope(conn).organization || Organization)

    if Organizations.onboarding_required?(scope(conn)) do
      redirect(conn, external: StarterKitWeb.ApiAuth.spa_url("/onboarding/edit"))
    else
      render_inertia(conn, "dashboard/show")
    end
  end
end
