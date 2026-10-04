defmodule StarterKit.OrganizationsTest do
  use StarterKit.DataCase, async: true

  import Swoosh.TestAssertions

  alias StarterKit.Accounts.Scope
  alias StarterKit.Organizations
  alias StarterKit.Organizations.{Invitation, Membership}

  test "a new user gets a personal organization as owner" do
    scope = scope_fixture()
    assert scope.organization.personal
    assert scope.membership.role == :owner
    assert Scope.full_access?(scope)
  end

  describe "invitations" do
    setup do
      %{scope: scope_fixture()}
    end

    test "are emailed, accepted once, and create the membership", %{scope: scope} do
      invitee = user_fixture()

      token =
        capture_token(
          &Organizations.create_invitation(
            scope,
            %{"email" => invitee.email, "role" => "admin"},
            &1
          )
        )

      assert_email_sent()

      invitee_scope = Scope.for_user(invitee)

      assert {:ok, %Membership{role: :admin}} =
               Organizations.accept_invitation(invitee_scope, token)

      assert {:error, :invalid_invitation} = Organizations.accept_invitation(invitee_scope, token)
    end

    test "must match the invited email", %{scope: scope} do
      token =
        capture_token(
          &Organizations.create_invitation(scope, %{"email" => "someone@example.com"}, &1)
        )

      assert {:error, :email_mismatch} =
               Organizations.accept_invitation(Scope.for_user(user_fixture()), token)
    end

    test "cannot invite an owner or an existing member", %{scope: scope} do
      assert {:error, changeset} =
               Organizations.create_invitation(
                 scope,
                 %{"email" => "a@example.com", "role" => "owner"},
                 & &1
               )

      assert "validation.invitation_owner" in errors_on(changeset).role

      assert {:error, changeset} =
               Organizations.create_invitation(scope, %{"email" => scope.user.email}, & &1)

      assert "validation.already_member" in errors_on(changeset).email
    end

    test "expire", %{scope: scope} do
      token =
        capture_token(&Organizations.create_invitation(scope, %{"email" => "late@example.com"}, &1))

      Repo.update_all(Invitation, [set: [expires_at: DateTime.add(DateTime.utc_now(), -1, :day)]],
        skip_org_id: true
      )

      assert {:error, :invalid_invitation} = Organizations.get_open_invitation(token)
    end
  end

  describe "memberships" do
    test "the last owner cannot leave or be demoted" do
      scope = scope_fixture()
      assert {:error, :last_owner} = Organizations.delete_membership(scope, scope.membership)

      assert {:error, changeset} =
               Organizations.update_membership(scope, scope.membership, %{"role" => "member"})

      assert "validation.last_owner" in errors_on(changeset).role
    end

    test "only owners create owners" do
      owner_scope = scope_fixture()
      admin = user_fixture()
      membership_fixture(owner_scope, admin, :admin)
      admin_scope = Organizations.scope_for(Scope.for_user(admin), owner_scope.organization.id)
      member = membership_fixture(owner_scope, user_fixture())

      assert {:error, changeset} =
               Organizations.update_membership(admin_scope, member, %{"role" => "owner"})

      assert "validation.owner_only" in errors_on(changeset).role

      assert {:ok, %Membership{role: :owner}} =
               Organizations.update_membership(owner_scope, member, %{"role" => "owner"})
    end
  end

  describe "switching organization" do
    test "only to organizations the user belongs to" do
      scope = scope_fixture()
      other = scope_fixture()
      assert {:error, :not_member} = Organizations.switch_organization(scope, other.organization.id)

      membership_fixture(other, scope.user)
      assert {:ok, switched} = Organizations.switch_organization(scope, other.organization.id)
      assert switched.organization.id == other.organization.id
    end
  end

  describe "onboarding" do
    test "a new organization's owner onboards once; a blank answer keeps the name" do
      scope = scope_fixture(user_fixture(), onboarded: false)
      assert Organizations.onboarding_required?(scope)

      assert {:ok, org} = Organizations.complete_onboarding(scope, %{"name" => "  "})
      assert org.name == scope.organization.name
      assert org.onboarded_at
      refute Organizations.onboarding_required?(%{scope | organization: org})
    end

    test "the answer renames the organization and is validated" do
      scope = scope_fixture(user_fixture(), onboarded: false)

      assert {:error, changeset} = Organizations.complete_onboarding(scope, %{"name" => "A"})
      assert errors_on(changeset).name != []
      assert {:ok, %{name: "Acme"}} = Organizations.complete_onboarding(scope, %{"name" => "Acme"})
    end

    test "members and an impersonating admin never see onboarding" do
      scope = scope_fixture(user_fixture(), onboarded: false)
      member = user_fixture()
      membership_fixture(scope, member, :member)

      refute Organizations.onboarding_required?(scope_fixture(member, onboarded: false))
      refute Organizations.onboarding_required?(Scope.put_impersonator(scope, superadmin_fixture()))
    end
  end
end
