defmodule StarterKit.PrivacyTest do
  use StarterKit.DataCase, async: true

  alias StarterKit.Accounts.User
  alias StarterKit.Organizations.Organization
  alias StarterKit.{Privacy, Repo}

  defp deleted?(%User{id: id}), do: is_nil(Repo.get(User, id))
  defp exists?(%Organization{id: id}), do: not is_nil(Repo.get(Organization, id))

  test "the only person in an organization deletes the account and the organization" do
    scope = scope_fixture()
    assert Privacy.deletion_blocker(scope) == nil

    assert {:ok, _} = Privacy.delete_account(scope)
    assert deleted?(scope.user)
    refute exists?(scope.organization)
  end

  test "the last owner of an organization with other people must transfer ownership first" do
    scope = scope_fixture()
    membership_fixture(scope, user_fixture(), :admin)

    assert {:transfer_ownership, %Organization{id: org_id}} = Privacy.deletion_blocker(scope)
    assert org_id == scope.organization.id
    assert {:error, {:transfer_ownership, _}} = Privacy.delete_account(scope)
    refute deleted?(scope.user)
  end

  test "an owner with another owner leaves; the organization stays for the others" do
    scope = scope_fixture()
    membership_fixture(scope, user_fixture(), :owner)

    assert {:ok, _} = Privacy.delete_account(scope)
    assert deleted?(scope.user)
    assert exists?(scope.organization)
  end

  test "a member of someone else's organization leaves it" do
    owner_scope = scope_fixture()
    member = user_fixture()
    membership_fixture(owner_scope, member, :member)
    member_scope = scope_fixture(member)

    assert {:ok, _} = Privacy.delete_account(member_scope)
    assert deleted?(member)
    assert exists?(owner_scope.organization)
  end

  test "an open subscription in an organization nobody else is in stops the deletion" do
    scope = scope_fixture()
    subscription_fixture(scope, %{status: "past_due"})

    assert {:subscription_active, _} = Privacy.deletion_blocker(scope)
    assert {:error, {:subscription_active, _}} = Privacy.delete_account(scope)
    refute deleted?(scope.user)
  end

  test "an ended subscription is billing history: the account goes, the organization stays" do
    scope = scope_fixture()
    subscription_fixture(scope, %{status: "canceled"})

    assert Privacy.deletion_blocker(scope) == nil
    assert {:ok, _} = Privacy.delete_account(scope)
    assert deleted?(scope.user)
    assert exists?(scope.organization)
  end
end
