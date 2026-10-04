defmodule StarterKit.Organizations.InvitationPolicy do
  @moduledoc "Owners and admins (full access) invite, list and revoke invitations."

  @behaviour StarterKit.Policy

  alias StarterKit.Accounts.Scope
  alias StarterKit.Organizations.{Invitation, OrganizationPolicy}

  @impl true
  def authorize(%Scope{} = scope, action, Invitation) when action in [:index, :new, :create],
    do: OrganizationPolicy.manager?(scope)

  def authorize(%Scope{} = scope, :delete, %Invitation{organization_id: org_id}),
    do: Scope.organization_id(scope) == org_id and OrganizationPolicy.manager?(scope)

  def authorize(_scope, _action, _resource), do: false
end
