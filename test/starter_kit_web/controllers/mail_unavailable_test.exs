defmodule StarterKitWeb.MailUnavailableTest do
  # Changes the global mailer config: not async.
  use StarterKitWeb.ConnCase, async: false

  import Swoosh.TestAssertions

  alias StarterKit.Accounts
  alias StarterKit.Accounts.UserToken
  alias StarterKit.Repo

  setup do
    mailer = Application.get_env(:starter_kit, StarterKit.Mailer)
    Application.put_env(:starter_kit, StarterKit.Mailer, adapter: Swoosh.Adapters.Logger)
    on_exit(fn -> Application.put_env(:starter_kit, StarterKit.Mailer, mailer) end)
  end

  test "sign-up says mail is unavailable and creates no account", %{conn: conn} do
    email = unique_email()
    conn = post(conn, ~p"/registration", %{"user" => %{"name" => "Ana", "email" => email}})

    assert redirected_to(conn) == ~p"/registration/new"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "can't send emails"
    assert Accounts.get_user_by_email(email) == nil
    assert Repo.aggregate(UserToken, :count) == 0
    assert_no_email_sent()
  end

  test "the sign-up and sign-in pages say it up front", %{conn: conn} do
    refute conn |> get(~p"/registration/new") |> inertia_props() |> Map.fetch!(:emailAvailable)
    refute conn |> get(~p"/session/new") |> inertia_props() |> Map.fetch!(:emailAvailable)
  end

  test "an old 'check your email' state is never shown", %{conn: conn} do
    page = conn |> init_test_session(link_sent_to: "old@example.com") |> get(~p"/session/new")
    assert is_nil(inertia_props(page).linkSentTo)
  end

  test "password sign-in still works", %{conn: conn} do
    user = user_fixture(password: "correct horse battery")

    conn =
      post(conn, ~p"/session", %{
        "user" => %{"email" => user.email, "password" => "correct horse battery"}
      })

    assert redirected_to(conn) == ~p"/dashboard"
  end

  test "a sign-in link request says mail is unavailable, never 'check your inbox'", %{conn: conn} do
    conn = post(conn, ~p"/magic-links", %{"user" => %{"email" => unique_email()}})

    assert redirected_to(conn) == ~p"/session/new"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "can't send emails"
    refute get_session(conn, :link_sent_to)
  end
end
