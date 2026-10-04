defmodule StarterKit.Organizations.OrganizationPolicy do
  @moduledoc "Members see their organization; owners and admins with full access change it."

  @behaviour StarterKit.Policy

  alias StarterKit.Accounts.Scope
  alias StarterKit.Organizations.Organization

  @impl true
  def authorize(%Scope{} = scope, :index, Organization), do: Scope.superadmin?(scope)

  def authorize(%Scope{} = scope, :show, %Organization{id: id}),
    do: Scope.organization_id(scope) == id or Scope.superadmin?(scope)

  def authorize(%Scope{} = scope, action, %Organization{id: id}) when action in [:edit, :update],
    do: Scope.organization_id(scope) == id and manager?(scope)

  # Buying or changing the plan: the same people who manage the organization.
  def authorize(%Scope{} = scope, :manage_billing, %Organization{id: id}),
    do: Scope.organization_id(scope) == id and manager?(scope)

  def authorize(%Scope{} = scope, :switch, %Organization{}), do: not is_nil(scope.user)

  def authorize(%Scope{user: user}, :create, Organization),
    do: not is_nil(user) and StarterKit.Organizations.mode() == :multi

  def authorize(_scope, _action, _resource), do: false

  @doc false
  def manager?(scope), do: Scope.role_in?(scope, [:owner, :admin]) and Scope.full_access?(scope)
end
