defmodule StarterKit.TenancyTest do
  @moduledoc """
  Tenant isolation. Every tenant schema gets a case here: a user of organization A
  cannot read or change rows of organization B through the context API.
  """
  use StarterKit.DataCase, async: true

  alias StarterKit.Organizations
  alias StarterKit.Organizations.{Invitation, Membership}
  alias StarterKit.Repo.TenantError

  setup do
    a = scope_fixture()
    b = scope_fixture()
    %{a: a, b: b}
  end

  test "an unscoped query on a tenant schema raises" do
    assert_raise TenantError, fn -> Repo.all(Membership) end
    assert [_ | _] = Repo.all(Membership, skip_org_id: true)
  end

  test "memberships", %{a: a, b: b} do
    assert Enum.all?(Organizations.list_memberships(a), &(&1.organization_id == a.organization.id))
    assert_raise Ecto.NoResultsError, fn -> Organizations.get_membership!(a, b.membership.id) end
  end

  test "invitations", %{a: a, b: b} do
    {:ok, invitation} = Organizations.create_invitation(b, %{"email" => "x@example.com"}, & &1)
    assert Organizations.list_invitations(a) == []
    assert_raise TenantError, fn -> Repo.all(Invitation) end
    assert_raise Ecto.NoResultsError, fn -> Organizations.get_invitation!(a, invitation.id) end
  end

  test "subscriptions", %{a: a, b: b} do
    subscription_fixture(b)
    assert StarterKit.Billing.current_subscription(a) == nil
    assert StarterKit.Billing.current_subscription(b).organization_id == b.organization.id
    assert_raise TenantError, fn -> Repo.all(StarterKit.Billing.Subscription) end
  end

  test "organizations", %{a: a, b: b} do
    assert_raise Ecto.NoResultsError, fn ->
      Organizations.get_organization!(a, b.organization.id)
    end
  end
end
