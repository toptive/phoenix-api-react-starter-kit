defmodule StarterKitWeb.MailUnavailableTest do
  use StarterKitWeb.ConnCase, async: false
  import Swoosh.TestAssertions
  alias StarterKit.Accounts
  alias StarterKit.Accounts.UserToken
  alias StarterKit.Repo

  setup %{conn: conn} do
    mailer = Application.get_env(:starter_kit, StarterKit.Mailer)
    Application.put_env(:starter_kit, StarterKit.Mailer, adapter: Swoosh.Adapters.Logger)
    on_exit(fn -> Application.put_env(:starter_kit, StarterKit.Mailer, mailer) end)
    %{conn: put_req_header(conn, "content-type", "application/json")}
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

  test "magic links refuse without writing tokens", %{conn: conn} do
    user = user_fixture()

    for path <- [~p"/api/v1/auth/magic-links"] do
      assert json_response(post(conn, path, %{email: user.email}), 503)["error"]["code"] ==
               "email_unavailable"
    end

    assert Repo.aggregate(UserToken, :count) == 0
    assert_no_email_sent()
  end

  test "invitations refuse before any write or email", %{conn: conn} do
    user = user_fixture(password: "correct horse battery")
    session = StarterKitWeb.ApiHelpers.sign_in(conn, user)
    auth = StarterKitWeb.ApiHelpers.bearer(conn, session["token"])

    response =
      post(auth, ~p"/api/v1/settings/invitations", %{
        email: unique_email(),
        role: "member",
        access: "full"
      })

    assert json_response(response, 503)["error"]["code"] == "email_unavailable"
    scope = StarterKit.Organizations.scope_for(Accounts.Scope.for_user(user))

    assert Repo.aggregate(StarterKit.Organizations.Invitation, :count,
             org_id: scope.organization.id
           ) == 0

    assert_no_email_sent()
  end
end
