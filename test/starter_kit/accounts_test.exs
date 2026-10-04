defmodule StarterKit.AccountsTest do
  use StarterKit.DataCase, async: true
  use Oban.Testing, repo: StarterKit.Repo

  import Swoosh.TestAssertions

  alias StarterKit.Accounts
  alias StarterKit.Accounts.{Scope, User, UserToken}

  describe "register_user/3" do
    test "creates an unconfirmed user and emails a magic link" do
      email = unique_email()
      attrs = %{"name" => "Ana", "email" => email, "terms_accepted" => "true"}

      {:ok, user} = Accounts.register_user(attrs, &"http://test/#{&1}")

      assert user.email == email
      assert is_nil(user.confirmed_at)
      assert is_nil(user.hashed_password)
      assert_email_sent(fn mail -> assert mail.to == [{"Ana", email}] end)
    end

    test "requires name and a valid, unique email" do
      existing = user_fixture()
      assert {:error, changeset} = Accounts.register_user(%{"name" => "", "email" => "nope"}, & &1)
      assert %{name: [_], email: ["validation.email_format"]} = errors_on(changeset)

      assert {:error, changeset} =
               Accounts.register_user(
                 %{"name" => "X", "email" => existing.email, "terms_accepted" => "true"},
                 & &1
               )

      assert "has already been taken" in errors_on(changeset).email
    end
  end

  describe "magic links" do
    test "confirm an unconfirmed user and expire their other tokens" do
      user = user_fixture(confirmed_at: nil)
      token = capture_token(&Accounts.deliver_login_instructions(user.email, &1))

      assert {:ok, {confirmed, _expired}} = Accounts.login_user_by_magic_link(token)
      assert confirmed.confirmed_at
      assert {:error, :not_found} = Accounts.login_user_by_magic_link(token)
    end

    test "do not reveal unknown emails" do
      assert :ok = Accounts.deliver_login_instructions("unknown@example.com", &"http://test/#{&1}")
      assert_no_email_sent()
    end
  end

  describe "passwords" do
    test "a password change expires every session" do
      user = user_fixture()
      _token = Accounts.generate_user_session_token(user)
      scope = Scope.for_user(user)

      assert {:ok, {user, expired}} =
               Accounts.update_user_password(scope, %{
                 "password" => "a long new password",
                 "password_confirmation" => "a long new password"
               })

      assert length(expired) == 1
      assert Accounts.get_user_by_email_and_password(user.email, "a long new password")
      refute Repo.get_by(UserToken, user_id: user.id)
    end

    test "is at least 12 characters" do
      scope = Scope.for_user(user_fixture())
      assert {:error, changeset} = Accounts.update_user_password(scope, %{"password" => "short"})
      assert errors_on(changeset).password != []
    end
  end

  describe "sessions" do
    test "record the device and can be revoked by their owner only" do
      user = user_fixture()
      Accounts.generate_user_session_token(user, %{user_agent: "Firefox", ip_address: "10.0.0.1"})
      [session] = Accounts.list_sessions(Scope.for_user(user))
      assert session.user_agent == "Firefox"

      other = Scope.for_user(user_fixture())
      assert {:error, :not_found} = Accounts.revoke_session(other, session.id)
      assert {:ok, _} = Accounts.revoke_session(Scope.for_user(user), session.id)
    end
  end

  describe "impersonation" do
    test "a superadmin impersonates a user with a reason, audited" do
      admin = superadmin_fixture()
      target = user_fixture()
      scope = Scope.for_user(admin)

      assert {:error, %Ecto.Changeset{}} =
               Accounts.start_impersonation(scope, target, %{"reason" => ""})

      assert {:ok, imp} = Accounts.start_impersonation(scope, target, %{"reason" => "Ticket 42"})
      assert imp.target_user_id == target.id

      assert Repo.get_by(StarterKit.Audit.AuditEvent,
               action: "impersonation.started",
               subject_id: target.id
             )
    end

    test "never another superadmin, never by a normal user" do
      admin = superadmin_fixture()

      assert {:error, :forbidden} =
               Accounts.start_impersonation(Scope.for_user(admin), superadmin_fixture(), %{
                 "reason" => "Ticket 42"
               })

      assert {:error, :forbidden} =
               Accounts.start_impersonation(Scope.for_user(user_fixture()), user_fixture(), %{
                 "reason" => "Ticket 42"
               })
    end
  end

  describe "google sign-in" do
    test "links an existing account by email, or creates a confirmed one" do
      existing = user_fixture(confirmed_at: nil)

      assert {:ok, linked} =
               Accounts.upsert_google_user(%{
                 uid: "g-1",
                 email: existing.email,
                 email_verified: true,
                 name: "X"
               })

      assert linked.id == existing.id and linked.google_uid == "g-1" and linked.confirmed_at

      assert {:ok, %User{} = created} =
               Accounts.upsert_google_user(%{
                 uid: "g-2",
                 email: unique_email(),
                 email_verified: true,
                 name: "New"
               })

      assert created.confirmed_at
    end

    test "refuses an email Google has not verified (no account takeover)" do
      existing = user_fixture()

      for verified <- [false, nil] do
        assert {:error, :email_not_verified} =
                 Accounts.upsert_google_user(%{
                   uid: "g-3",
                   email: existing.email,
                   email_verified: verified,
                   name: "Attacker"
                 })
      end

      assert Repo.get!(User, existing.id).google_uid == nil
      refute Repo.get_by(User, google_uid: "g-3")
    end
  end
end
