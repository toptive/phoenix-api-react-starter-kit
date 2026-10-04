defmodule StarterKit.NotificationsDeliveryTest do
  # Changes the global mailer config: not async.
  use StarterKit.DataCase, async: false

  @moduletag :capture_log

  import StarterKit.Fixtures
  import Swoosh.TestAssertions

  alias StarterKit.{Accounts, Notifications, Organizations}

  @job %{
    "recipient" => %{"email" => "ana@client.com", "name" => "Ana", "locale" => "en"},
    "kind" => "magic_link",
    "data" => %{"url" => "https://app.example.com/x"}
  }

  setup do
    mailer = Application.get_env(:starter_kit, StarterKit.Mailer)

    on_exit(fn ->
      Application.put_env(:starter_kit, StarterKit.Mailer, mailer)
      Application.delete_env(:starter_kit, :mail_allowed_recipients)
    end)
  end

  defp without_mail_adapter,
    do: Application.put_env(:starter_kit, StarterKit.Mailer, adapter: Swoosh.Adapters.Logger)

  describe "MAIL_ALLOWED_RECIPIENTS" do
    test "unset (production) lets everyone get mail" do
      assert Notifications.deliver_now(@job) == :ok
      assert_email_sent(to: [{"Ana", "ana@client.com"}])
    end

    test "set: another address is dropped, never sent" do
      Application.put_env(:starter_kit, :mail_allowed_recipients, ["qa@toptive.co", "*@team.dev"])

      assert Notifications.deliver_now(@job) == {:cancel, :recipient_not_allowed}
      assert_no_email_sent()
    end

    test "set: an exact address or a *@domain pattern gets mail, in any case" do
      Application.put_env(:starter_kit, :mail_allowed_recipients, ["QA@toptive.co", "*@Team.dev"])

      assert Notifications.recipient_allowed?("qa@toptive.co")
      assert Notifications.recipient_allowed?("bo@team.dev")
      refute Notifications.recipient_allowed?("bo@team.dev.evil.com")
      refute Notifications.recipient_allowed?("bo@notteam.dev")
      refute Notifications.recipient_allowed?("qa@toptive.co.evil.com")
    end
  end

  describe "email_available?" do
    test "true for the test and dev adapters and for Postmark with a key" do
      assert Notifications.email_available?()

      Application.put_env(:starter_kit, StarterKit.Mailer,
        adapter: Swoosh.Adapters.Postmark,
        api_key: "k"
      )

      assert Notifications.email_available?()

      Application.put_env(:starter_kit, StarterKit.Mailer,
        adapter: Swoosh.Adapters.Postmark,
        api_key: " "
      )

      refute Notifications.email_available?()
    end

    test "without an adapter the job waits instead of a silent drop" do
      without_mail_adapter()
      refute Notifications.email_available?()

      assert Notifications.deliver_now(@job) == {:snooze, 3600}
      assert_no_email_sent()
    end

    test "sign-up, sign-in links and email changes refuse before any write" do
      assert Accounts.email_sign_in_available?()
      without_mail_adapter()
      refute Accounts.email_sign_in_available?()
      url = &"https://app.example.com/#{&1}"

      assert Accounts.register_user(%{"name" => "Ana", "email" => "ana@client.com"}, url) ==
               {:error, :email_unavailable}

      assert Accounts.get_user_by_email("ana@client.com") == nil

      assert Accounts.deliver_login_instructions("ana@client.com", url) ==
               {:error, :email_unavailable}

      scope = scope_fixture()

      assert Accounts.request_email_change(scope, %{"email" => "new@client.com"}, url) ==
               {:error, :email_unavailable}

      assert Organizations.create_invitation(scope, %{"email" => "bo@client.com"}, url) ==
               {:error, :email_unavailable}

      assert Organizations.list_invitations(scope) == []
    end
  end

  test "every kind belongs to a group" do
    assert Notifications.group(:magic_link) == :access
    assert Notifications.group("renewal_notice") == :transactional

    assert Enum.all?(
             Notifications.kinds(),
             &(Notifications.group(&1) in [:access, :transactional, :optional])
           )
  end
end
