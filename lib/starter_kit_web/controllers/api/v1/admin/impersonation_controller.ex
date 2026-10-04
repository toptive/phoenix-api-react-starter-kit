defmodule StarterKitWeb.Api.V1.Admin.ImpersonationController do
  @moduledoc "Superadmin impersonation API."
  use StarterKitWeb, :controller
  alias StarterKit.Accounts
  alias StarterKit.Accounts.User
  alias StarterKitWeb.ApiAuth

  def create(conn, %{"id" => id} = params) do
    conn = authorize!(conn, :impersonate, User)

    case Accounts.start_api_impersonation(
           scope(conn),
           id,
           Map.take(params, ["reason"]),
           ApiAuth.device(conn)
         ) do
      {:ok, session} ->
        conn |> put_status(201) |> render_data({Serializers.AuthSessionSerializer, session})

      {:error, reason} ->
        ApiAuth.error(conn, reason)
    end
  end
end
