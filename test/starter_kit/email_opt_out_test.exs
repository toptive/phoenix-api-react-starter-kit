defmodule StarterKit.EmailOptOutTest do
  # Changes the global sender config in one test: not async.
  use StarterKit.DataCase, async: false

  import StarterKit.Fixtures
  import Swoosh.TestAssertions

  alias StarterKit.{Accounts, Mailer, Notifications, Repo}
  alias StarterKit.Audit.AuditEvent
  alias StarterKit.Notifications.Email

  @news %{title: "Shared folders", summary: "Share a folder.", url: "https://app.example.com/news"}

  defp token(url), do: url |> URI.parse() |> Map.fetch!(:path) |> Path.split() |> Enum.at(2)

  describe "optional mail to a user" do
    test "carries a signed unsubscribe URL in the footer and the List-Unsubscribe header" do
      user = user_fixture()
      assert {:ok, %Oban.Job{}} = Notifications.notify(user, :product_update, @news)

      assert_email_sent(fn email ->
        "<" <> url = String.trim_trailing(email.headers["List-Unsubscribe"], ">")
        assert url =~ ~r{/email-subscriptions/[^/]+/opt-out$}
        assert email.html_body =~ ~s(href="#{url}")
        assert {:ok, %{id: id}} = url |> token() |> Accounts.get_user_by_unsubscribe_token()
        assert id == user.id
        assert email.html_body =~ ~s(href="#{Notifications.preferences_url()}")
      end)
    end

    test "is not queued once the user unsubscribed; access mail still is" do
      user = user_fixture() |> Ecto.Changeset.change(optional_emails: false) |> Repo.update!()

      assert Notifications.notify(user, :product_update, @news) == {:ok, :opted_out}
      assert_no_email_sent()

      assert {:ok, %Oban.Job{}} =
               Notifications.notify(user, :magic_link, %{url: "https://x.example.com"})

      assert_email_sent(to: [{user.name, user.email}])
    end

    test "to a non-user needs an explicit unsubscribe_url" do
      assert_raise ArgumentError, fn ->
        Notifications.notify(%{email: "a@b.com"}, :product_update, @news)
      end
    end
  end

  test "RFC 8058: one-click header only for an https URL" do
    recipient = %{"email" => "bo@example.com", "name" => "Bo", "locale" => "en"}
    data = %{"title" => "T", "summary" => "S", "url" => "https://x.example.com"}

    https =
      Email.build(
        recipient,
        "product_update",
        Map.put(data, "unsubscribe_url", "https://a.com/u"),
        :optional
      )

    assert https.headers["List-Unsubscribe"] == "<https://a.com/u>"
    assert https.headers["List-Unsubscribe-Post"] == "List-Unsubscribe=One-Click"

    http =
      Email.build(
        recipient,
        "product_update",
        Map.put(data, "unsubscribe_url", "http://a.com/u"),
        :optional
      )

    refute Map.has_key?(http.headers, "List-Unsubscribe-Post")
  end

  describe "unsubscribe tokens" do
    test "a tampered token, a changed address or a deleted user names nobody" do
      user = user_fixture()
      good = user.id |> Notifications.unsubscribe_url(user.email) |> token()

      assert Accounts.get_user_by_unsubscribe_token(good <> "x") == :error
      assert Accounts.get_user_by_unsubscribe_token("nonsense") == :error

      user |> Ecto.Changeset.change(email: "new-#{user.email}") |> Repo.update!()
      assert Accounts.get_user_by_unsubscribe_token(good) == :error

      other = user_fixture()
      other_token = other.id |> Notifications.unsubscribe_url(other.email) |> token()
      Repo.delete!(other)
      assert Accounts.unsubscribe_from_optional_emails(other_token) == :error
    end

    test "unsubscribing is idempotent and audited once" do
      user = user_fixture()
      token = user.id |> Notifications.unsubscribe_url(user.email) |> token()

      assert Accounts.unsubscribe_from_optional_emails(token) == :ok
      assert Accounts.unsubscribe_from_optional_emails(token) == :ok
      refute Repo.reload!(user).optional_emails

      assert Repo.aggregate(
               from(e in AuditEvent, where: e.action == "user.optional_emails_stopped"),
               :count
             ) == 1
    end
  end

  test "the sender follows the recipient's locale, else the default" do
    default = Application.get_env(:starter_kit, :mail_from)
    assert Mailer.from("es") == default

    Application.put_env(:starter_kit, :mail_from_by_locale, %{
      "es" => {"Equipo", "hola@example.com"}
    })

    on_exit(fn -> Application.put_env(:starter_kit, :mail_from_by_locale, %{}) end)

    assert Mailer.from("es") == {"Equipo", "hola@example.com"}
    assert Mailer.from("en") == default
  end

  describe "update_email_preferences/2 (settings)" do
    defp audited(action),
      do: Repo.aggregate(from(e in AuditEvent, where: e.action == ^action), :count)

    test "subscribes again after an unsubscribe, audited once per change" do
      user = user_fixture() |> Ecto.Changeset.change(optional_emails: false) |> Repo.update!()
      scope = StarterKit.Accounts.Scope.for_user(user)

      assert {:ok, %{optional_emails: true} = user} =
               Accounts.update_email_preferences(scope, %{"optional_emails" => true})

      assert audited("user.optional_emails_started") == 1

      scope = StarterKit.Accounts.Scope.for_user(user)
      assert {:ok, _} = Accounts.update_email_preferences(scope, %{"optional_emails" => true})
      assert audited("user.optional_emails_started") == 1

      assert {:ok, %{optional_emails: false}} =
               Accounts.update_email_preferences(scope, %{"optional_emails" => false})

      assert audited("user.optional_emails_stopped") == 1
    end

    test "rejects a missing value" do
      scope = StarterKit.Accounts.Scope.for_user(user_fixture())

      assert {:error, changeset} =
               Accounts.update_email_preferences(scope, %{"optional_emails" => nil})

      assert %{optional_emails: [_]} = errors_on(changeset)
    end
  end
end
