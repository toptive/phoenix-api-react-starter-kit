defmodule StarterKitWeb.Admin.UserController do
  @moduledoc "Find a user, see their organizations, change the global role."
  use StarterKitWeb, :controller
  use Typelizer.InertiaPage

  alias StarterKit.{Accounts, Organizations}
  alias StarterKit.Accounts.User

  page "admin/users/index",
    props: [
      users: {:list, Serializers.UserSerializer},
      pagination: Serializers.PaginationSerializer,
      q: :string
    ]

  page "admin/users/show",
    props: [
      user: Serializers.UserSerializer,
      organizations: {:list, Serializers.OrganizationSerializer},
      roles: {:list, :string}
    ]

  def index(conn, params) do
    conn = authorize!(conn, :index, User)
    page = Accounts.list_users(scope(conn), params)

    render_inertia(conn, "admin/users/index", %{
      users: Serializers.UserSerializer.serialize_many(page.entries),
      pagination: Serializers.PaginationSerializer.serialize(page),
      q: params["q"] || ""
    })
  end

  def show(conn, %{"id" => id}) do
    user = Accounts.get_user!(scope(conn), id)
    conn = authorize!(conn, :show, user)
    user_scope = Accounts.Scope.for_user(user)

    render_inertia(conn, "admin/users/show", %{
      user: Serializers.UserSerializer.serialize(user),
      organizations:
        Serializers.OrganizationSerializer.serialize_many(
          Organizations.list_user_organizations(user_scope)
        ),
      roles: Enum.map(User.roles(), &Atom.to_string/1)
    })
  end

  def update(conn, %{"id" => id, "user" => params}) do
    user = Accounts.get_user!(scope(conn), id)
    conn = authorize!(conn, :update, user)

    case Accounts.update_user_role(scope(conn), user, params) do
      {:ok, _} -> put_flash_t(conn, :info, "flash.admin.user_updated")
      {:error, changeset} -> assign_changeset_errors(conn, changeset)
    end
    |> redirect(to: ~p"/admin/users/#{id}")
  end
end
