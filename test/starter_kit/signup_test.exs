defmodule StarterKit.SignupTest do
  # Not async: SIGNUP_MODE is global application config.
  use StarterKit.DataCase, async: false

  import Swoosh.TestAssertions

  alias StarterKit.{Accounts, Legal, Organizations}
  alias StarterKit.Accounts.{Scope, User}
  alias StarterKit.Audit.AuditEvent
  alias StarterKit.Legal.LegalAcceptance

  setup do
    on_exit(fn -> Application.put_env(:starter_kit, :signup_mode, :open) end)
  end

  defp signup_mode(mode), do: Application.put_env(:starter_kit, :signup_mode, mode)

  defp attrs(extra \\ %{}),
    do: Map.merge(%{"name" => "Ana", "email" => unique_email(), "terms_accepted" => "true"}, extra)

  defp publish(slug) do
    scope = Scope.for_user(superadmin_fixture())
    [document] = scope |> Legal.list_documents() |> Enum.filter(&(&1.slug == slug))

    {:ok, version} =
      Legal.create_version(
        scope,
        document,
        %{"titles" => %{"en" => slug}, "bodies" => %{"en" => "Text"}},
        publish: true
      )

    version
  end

  describe "consent at sign-up" do
    test "the user and one acceptance per published terms/privacy version are written together" do
      terms = publish("terms")
      privacy = publish("privacy")

      {:ok, user} = Accounts.register_user(attrs(), & &1, ip_address: "203.0.113.9")

      acceptances = Repo.all(from a in LegalAcceptance, where: a.user_id == ^user.id)

      assert acceptances |> Enum.map(& &1.legal_document_version_id) |> Enum.sort() ==
               Enum.sort([terms.id, privacy.id])

      assert Enum.all?(acceptances, &(&1.ip_address == "203.0.113.9"))

      event = Repo.get_by!(AuditEvent, action: "user.registered", subject_id: user.id)
      assert Enum.sort(event.metadata["accepted"]) == ["privacy", "terms"]
    end

    test "without the checkbox nothing is written and no mail leaves" do
      publish("terms")
      email = unique_email()

      assert {:error, changeset} =
               Accounts.register_user(attrs(%{"email" => email, "terms_accepted" => "false"}), & &1)

      assert errors_on(changeset).terms_accepted == ["validation.terms_required"]
      refute Accounts.get_user_by_email(email)
      assert Repo.aggregate(LegalAcceptance, :count) == 0
      assert_no_email_sent()
    end

    test "an unpublished document is skipped (nothing to accept yet)" do
      publish("terms")
      {:ok, user} = Accounts.register_user(attrs(), & &1)

      assert [%LegalAcceptance{}] =
               Repo.all(from a in LegalAcceptance, where: a.user_id == ^user.id)
    end
  end

  describe "SIGNUP_MODE" do
    test "closed refuses every new account before any write, Google included" do
      signup_mode(:closed)
      email = unique_email()

      assert {:error, :signup_closed} =
               Accounts.register_user(attrs(%{"email" => email}), & &1, invited: true)

      assert {:error, :signup_closed} =
               Accounts.upsert_google_user(%{uid: "g-c", email: email, email_verified: true})

      refute Accounts.get_user_by_email(email)
      assert_no_email_sent()
    end

    test "invite admits only an email with an open invitation" do
      signup_mode(:invite)
      scope = scope_fixture()
      invited = unique_email()

      {:ok, _} = Organizations.create_invitation(scope, %{"email" => invited}, & &1)

      assert {:error, :invitation_required} = Organizations.register_user(attrs(), & &1)

      assert {:error, :invitation_required} =
               Organizations.upsert_google_user(%{
                 uid: "g-i",
                 email: unique_email(),
                 email_verified: true
               })

      assert {:ok, %User{}} =
               Organizations.register_user(attrs(%{"email" => String.upcase(invited)}), & &1)
    end

    test "an existing user still signs in with Google when sign-up is closed" do
      signup_mode(:closed)
      user = user_fixture()

      assert {:ok, %User{id: id}} =
               Accounts.upsert_google_user(%{uid: "g-e", email: user.email, email_verified: true})

      assert id == user.id
    end
  end

  describe "bootstrap_superadmin/1" do
    test "creates a confirmed superadmin without a password, once" do
      assert {:ok, admin} = Accounts.bootstrap_superadmin(" first@example.com ")
      assert admin.email == "first@example.com"
      assert admin.role == :superadmin and admin.confirmed_at
      assert is_nil(admin.hashed_password)
      assert Repo.get_by(AuditEvent, action: "user.superadmin_bootstrapped", subject_id: admin.id)

      assert {:error, :already_bootstrapped} = Accounts.bootstrap_superadmin(unique_email())
    end

    test "promotes an existing account" do
      user = user_fixture(confirmed_at: nil)
      assert {:ok, admin} = Accounts.bootstrap_superadmin(user.email)
      assert admin.id == user.id and admin.role == :superadmin and admin.confirmed_at
    end

    test "is refused when any superadmin exists" do
      superadmin_fixture()
      user = user_fixture()

      assert {:error, :already_bootstrapped} = Accounts.bootstrap_superadmin(user.email)
      assert Repo.get!(User, user.id).role == :user
    end

    test "rejects an invalid email" do
      assert {:error, %Ecto.Changeset{}} = Accounts.bootstrap_superadmin("nope")
    end
  end
end
