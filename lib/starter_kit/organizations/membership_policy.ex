defmodule StarterKit.Organizations.MembershipPolicy do
  @moduledoc """
  Every member sees the member list. Owners and admins (full access) change roles and
  remove people. Anyone may leave (destroy their own membership).
  Only owners may promote someone to owner or change an owner.
  """

  @behaviour StarterKit.Policy

  alias StarterKit.Accounts.Scope
  alias StarterKit.Organizations.{Membership, OrganizationPolicy}

  @impl true
  def authorize(%Scope{} = scope, :index, Membership), do: not is_nil(scope.membership)

  def authorize(%Scope{} = scope, :update, Membership), do: OrganizationPolicy.manager?(scope)
  def authorize(%Scope{} = scope, :delete, Membership), do: not is_nil(scope.membership)

  def authorize(%Scope{user: %{id: user_id}} = scope, :delete, %Membership{user_id: user_id} = m),
    do: same_org?(scope, m)

  def authorize(%Scope{} = scope, action, %Membership{} = m) when action in [:update, :delete] do
    same_org?(scope, m) and OrganizationPolicy.manager?(scope) and
      (m.role != :owner or Scope.role_in?(scope, [:owner]))
  end

  def authorize(_scope, _action, _resource), do: false

  defp same_org?(scope, %Membership{organization_id: org_id}),
    do: Scope.organization_id(scope) == org_id
end
