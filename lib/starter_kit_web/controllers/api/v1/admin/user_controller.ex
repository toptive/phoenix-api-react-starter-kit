defmodule StarterKitWeb.Api.V1.Admin.UserController do
  @moduledoc "Superadmin user API."
  use StarterKitWeb, :controller
  alias StarterKit.Accounts
  alias StarterKit.Accounts.User
  alias StarterKit.Organizations
  alias StarterKitWeb.ApiAuth

  def index(conn, params) do
    conn = authorize!(conn, :index, User)
    page = Accounts.list_users(scope(conn), params)

    render_collection(conn, page.entries, Serializers.UserSerializer, %{
      pagination: Serializers.PaginationSerializer.serialize(page)
    })
  end

  def show(conn, %{"id" => id}) do
    conn = authorize!(conn, :show, User)

    case Organizations.admin_user_detail(scope(conn), id) do
      {:ok, detail} -> render_data(conn, {Serializers.AdminUserDetailSerializer, detail})
      {:error, reason} -> ApiAuth.error(conn, reason)
    end
  end

  def update(conn, %{"id" => id} = params) do
    conn = authorize!(conn, :update, User)

    case Accounts.admin_update_user(scope(conn), id, Map.take(params, ["role"])) do
      {:ok, user} -> render_data(conn, {Serializers.UserSerializer, user})
      {:error, reason} -> ApiAuth.error(conn, reason)
    end
  end
end
