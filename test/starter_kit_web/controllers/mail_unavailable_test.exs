defmodule StarterKitWeb.MailUnavailableTest do
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

  test "registration refuses before writing when mail is unavailable", %{conn: conn} do
    email = unique_email()

    result =
      post(conn, ~p"/api/v1/auth/registrations", %{name: "Ana", email: email, termsAccepted: true})

    assert json_response(result, 503)["error"]["code"] == "email_unavailable"
    refute Accounts.get_user_by_email(email)
    assert Repo.aggregate(UserToken, :count) == 0
    assert_no_email_sent()
  end

  test "bootstrap exposes availability", %{conn: conn} do
    refute json_response(get(conn, ~p"/api/v1/bootstrap"), 200)["data"]["app"]["emailAvailable"]
  end

  test "password sign-in works without mail", %{conn: conn} do
    user = user_fixture(password: "correct horse battery")

    assert json_response(
             post(conn, ~p"/api/v1/auth/sessions", %{
               email: user.email,
               password: "correct horse battery"
             }),
             201
           )["data"]["token"]
  end

  test "magic links and password resets refuse without writing tokens", %{conn: conn} do
    user = user_fixture()

    for path <- [~p"/api/v1/auth/magic-links", ~p"/api/v1/auth/password-resets"] do
      assert json_response(post(conn, path, %{email: user.email}), 503)["error"]["code"] ==
               "email_unavailable"
    end

    assert Repo.aggregate(UserToken, :count) == 0
    assert_no_email_sent()
  end
end
