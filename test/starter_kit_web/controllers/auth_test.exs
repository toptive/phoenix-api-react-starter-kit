defmodule StarterKitWeb.AuthTest do
  use StarterKitWeb.ConnCase, async: true

  import Swoosh.TestAssertions

  alias StarterKit.Accounts

  describe "registration" do
    test "creates the user, emails the link and asks to check the inbox", %{conn: conn} do
      email = unique_email()
      user = %{"name" => "Ana", "email" => email, "termsAccepted" => true}
      conn = post(conn, ~p"/registration", %{"user" => user})
      assert redirected_to(conn) == ~p"/session/new"
      assert_email_sent()

      # The sign-in page says where the link went, once.
      page = conn |> recycle() |> get(~p"/session/new")
      assert inertia_props(page).linkSentTo == email
      assert inertia_props(page).emailAvailable

      assert page
             |> recycle()
             |> get(~p"/session/new")
             |> inertia_props()
             |> Map.get(:linkSentTo)
             |> is_nil()
    end

    test "returns translated errors keyed by field", %{conn: conn} do
      conn = post(conn, ~p"/registration", %{"user" => %{"name" => "", "email" => "x"}})
      assert redirected_to(conn) == ~p"/registration/new"
      errors = get_session(conn, "inertia_errors")
      assert errors["email"] =~ "full email"
    end
  end

  describe "magic link" do
    test "the page behind the link signs in only after the button", %{conn: conn} do
      user = user_fixture(confirmed_at: nil)
      token = capture_token(&Accounts.deliver_login_instructions(user.email, &1))

      page = get(conn, ~p"/magic-links/#{token}")
      assert inertia_component(page) == "magic-links/show"
      assert inertia_props(page).email == user.email

      conn = post(conn, ~p"/session", %{"user" => %{"token" => token}})
      assert redirected_to(conn) == ~p"/dashboard"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Your account is ready"
      assert get_session(conn, :user_token)
      assert_received {:analytics, %{event: "signup_confirmed", distinct_id: id}}
      assert id == user.id
    end

    test "an unknown email still answers the same", %{conn: conn} do
      conn = post(conn, ~p"/magic-links", %{"user" => %{"email" => "ghost@example.com"}})
      assert redirected_to(conn) == ~p"/session/new"
      assert_no_email_sent()
    end
  end

  describe "password sign-in" do
    test "works with the right password and records the device", %{conn: conn} do
      user = user_fixture(password: "correct horse battery")

      conn =
        conn
        |> put_req_header("user-agent", "TestBrowser")
        |> post(~p"/session", %{
          "user" => %{"email" => user.email, "password" => "correct horse battery"}
        })

      assert redirected_to(conn) == ~p"/dashboard"
      [session] = Accounts.list_sessions(StarterKit.Accounts.Scope.for_user(user))
      assert session.user_agent == "TestBrowser"
    end

    test "fails with a translated error", %{conn: conn} do
      user = user_fixture(password: "correct horse battery")
      conn = post(conn, ~p"/session", %{"user" => %{"email" => user.email, "password" => "wrong"}})
      assert redirected_to(conn) == ~p"/session/new"
      assert get_session(conn, "inertia_errors")["password"] =~ "don't match"
    end

    test "is rate limited per IP", %{conn: conn} do
      conn = %{conn | remote_ip: {10, 9, 8, System.unique_integer([:positive]) |> rem(250)}}

      for _ <- 1..10,
          do: post(conn, ~p"/session", %{"user" => %{"email" => "a@b.c", "password" => "x"}})

      conn = post(conn, ~p"/session", %{"user" => %{"email" => "a@b.c", "password" => "x"}})
      assert conn.status == 303
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Too many attempts"
    end
  end

  test "signing out", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})
    conn = delete(conn, ~p"/session")
    assert redirected_to(conn) == ~p"/"
    refute get_session(conn, :user_token)
  end

  test "guests are sent to sign in, then back", %{conn: conn} do
    conn = get(conn, ~p"/settings/profile/edit")
    assert redirected_to(conn) == ~p"/session/new"
    assert get_session(conn, :user_return_to) == ~p"/settings/profile/edit"
  end
end
