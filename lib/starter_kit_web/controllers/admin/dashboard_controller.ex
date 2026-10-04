defmodule StarterKitWeb.Admin.DashboardController do
  @moduledoc "Admin home: counts and entry points."
  use StarterKitWeb, :controller
  use Typelizer.InertiaPage

  alias StarterKit.{Accounts, Organizations}
  alias StarterKit.Accounts.User

  page "admin/dashboard/show", props: [stats: {:object, users: :integer, organizations: :integer}]

  def show(conn, _params) do
    conn = authorize!(conn, :index, User)

    render_inertia(conn, "admin/dashboard/show", %{
      stats: %{users: Accounts.count_users(), organizations: Organizations.count_organizations()}
    })
  end
end
