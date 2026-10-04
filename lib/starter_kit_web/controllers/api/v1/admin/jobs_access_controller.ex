defmodule StarterKitWeb.Api.V1.Admin.JobsAccessController do
  @moduledoc "Superadmin jobs access API."
  use StarterKitWeb, :controller
  alias StarterKit.Accounts.User
  alias StarterKitWeb.JobsAccess

  def create(conn, _params) do
    conn = authorize!(conn, :index, User)

    case JobsAccess.create(scope(conn)) do
      {:ok, access} ->
        conn |> put_status(201) |> render_data({Serializers.JobsAccessSerializer, access})

      {:error, reason} ->
        StarterKitWeb.ApiAuth.error(conn, reason)
    end
  end
end
