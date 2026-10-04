defmodule StarterKit.Billing.SubscriptionPolicy do
  @moduledoc "Members see their organization's plan; owners and admins (full access) manage it."

  @behaviour StarterKit.Policy

  alias StarterKit.Accounts.Scope
  alias StarterKit.Billing.Subscription
  alias StarterKit.Organizations.OrganizationPolicy

  @impl true
  def authorize(%Scope{} = scope, :show, %Subscription{organization_id: org_id}),
    do: Scope.organization_id(scope) == org_id

  def authorize(%Scope{} = scope, :update, %Subscription{organization_id: org_id}),
    do: Scope.organization_id(scope) == org_id and OrganizationPolicy.manager?(scope)

  def authorize(_scope, _action, _resource), do: false
end
