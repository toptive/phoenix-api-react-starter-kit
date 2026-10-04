defmodule StarterKitWeb.Authorization do
  @moduledoc """
  Pundit for Phoenix. Imported in every controller.

      conn = authorize!(conn, :update, organization)     # struct → its policy
      conn = authorize!(conn, :index, Membership)         # schema module → its policy
      conn = skip_authorization(conn)                     # public or self-evident actions

  `authorize!/3` raises `StarterKitWeb.NotAuthorizedError` (403). The
  `StarterKitWeb.Plugs.VerifyAuthorized` plug fails any authenticated action that did
  neither (like Pundit's `verify_authorized`), and `test/architecture` checks it
  statically.
  """

  import Plug.Conn

  alias StarterKit.Policy

  @doc "Authorizes `action` on `resource` for the current scope or raises (403)."
  def authorize!(conn, action, resource) do
    if Policy.allowed?(conn.assigns[:current_scope], action, resource) do
      put_private(conn, :authorized, true)
    else
      raise StarterKitWeb.NotAuthorizedError, action: action, resource: resource
    end
  end

  @doc "True when the current scope may perform `action` (for UI permissions in props)."
  def can?(conn, action, resource),
    do: Policy.allowed?(conn.assigns[:current_scope], action, resource)

  @doc "Marks the action as deliberately not needing a policy check."
  def skip_authorization(conn), do: put_private(conn, :authorized, true)
end

defmodule StarterKitWeb.NotAuthorizedError do
  @moduledoc "Raised by `authorize!/3`; rendered as 403."
  defexception [:action, :resource, plug_status: 403]

  @impl true
  def message(%{action: action, resource: resource}) do
    name =
      case resource do
        %module{} -> inspect(module)
        module -> inspect(module)
      end

    "not authorized to #{action} #{name}"
  end
end
