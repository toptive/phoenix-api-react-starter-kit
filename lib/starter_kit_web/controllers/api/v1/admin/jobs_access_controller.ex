defmodule StarterKitWeb.Api.V1.Admin.JobsAccessController do
  @moduledoc "Superadmin jobs access API."
  use StarterKitWeb, :controller
  alias StarterKit.Accounts.User
  alias StarterKitWeb.JobsAccess

  def create(conn, _params) do
    conn = authorize!(conn, :index, User)
    conn |> JobsAccess.mint(scope(conn).session.id) |> send_resp(204, "")
  end
end
