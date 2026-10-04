defmodule StarterKitWeb.Api.V1.Admin.DashboardController do
  @moduledoc "Superadmin dashboard API."
  use StarterKitWeb, :controller
  alias StarterKit.Accounts.User
  alias StarterKit.Organizations

  def show(conn, _params) do
    conn = authorize!(conn, :index, User)
    render_data(conn, {Serializers.AdminStatsSerializer, Organizations.admin_stats()})
  end
end
