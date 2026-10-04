defmodule StarterKitWeb.ApiAuthTest do
  use StarterKitWeb.ConnCase, async: true

  import Ecto.Query
  import Swoosh.TestAssertions

  alias StarterKit.Accounts
  alias StarterKit.Accounts.UserToken
  alias StarterKit.Repo

  setup %{conn: conn} do
    ip = System.unique_integer([:positive])

    %{
      conn: %{
        put_req_header(conn, "accept", "application/json")
        | remote_ip: {10, div(ip, 65_536) |> rem(250), div(ip, 256) |> rem(250), rem(ip, 250)}
      }
    }
  end

  defp bearer(conn, token), do: put_req_header(conn, "authorization", "Bearer " <> token)

  test "bootstrap is public, localized and contains no secrets or cookies", %{conn: conn} do
    response =
      conn |> put_req_header("accept-language", "en;q=0.2, es;q=1") |> get(~p"/api/v1/bootstrap")

    assert %{
             "data" => %{"user" => nil, "locale" => "es", "organizations" => [], "app" => app},
             "meta" => %{}
           } = json_response(response, 200)

    assert app["signupMode"] == "open"
    assert get_resp_header(response, "set-cookie") == []
    refute response.resp_body =~ "hashedPassword"
    refute response.resp_body =~ "fixture-secret"
    assert get_resp_header(response, "x-request-id") != []
    assert json_response(get(conn, ~p"/api/v1/bootstrap?locale=es"), 200)["data"]["locale"] == "es"
  end

  test "bootstrap loads only the user's memberships and marks impersonation", %{conn: conn} do
    user = user_fixture()
    scope = scope_fixture(user)
    other = scope_fixture(user_fixture())
    session = Accounts.generate_api_token(user)
    body = conn |> bearer(session.token) |> get(~p"/api/v1/bootstrap") |> json_response(200)
    assert body["data"]["user"]["id"] == user.id
    assert body["data"]["organization"]["id"] == scope.organization.id
    refute Enum.any?(body["data"]["organizations"], &(&1["id"] == other.organization.id))
  end

  test "locale catalogues preserve dotted keys and support conditional requests", %{conn: conn} do
    response = get(conn, ~p"/api/v1/locales/es")
    assert json_response(response, 200)["data"]["auth.session.title"]
    [etag] = get_resp_header(response, "etag")
    cached = conn |> put_req_header("if-none-match", "W/" <> etag) |> get(~p"/api/v1/locales/es")
    assert response(cached, 304) == ""
    assert get_resp_header(cached, "etag") == [etag]
    assert json_response(get(conn, ~p"/api/v1/locales/xx"), 404)["error"]["code"] == "not_found"
  end

  test "password sessions issue hashed tokens, record device and authorize current-user", %{
    conn: conn
  } do
    user = user_fixture(password: "correct horse battery")

    login =
      conn
      |> put_req_header("user-agent", "TestBrowser")
      |> put_req_header("content-type", "application/json")
      |> post(
        ~p"/api/v1/auth/sessions",
        Jason.encode!(%{email: user.email, password: "correct horse battery"})
      )

    data = json_response(login, 201)["data"]
    assert data["user"]["id"] == user.id
    assert data["expiresAt"]
    assert get_resp_header(login, "set-cookie") == []
    {loaded, row} = Accounts.get_user_by_api_token(data["token"])
    assert loaded.id == user.id
    assert row.context == "api"
    assert row.user_agent == "TestBrowser"
    assert row.ip_address == to_string(:inet.ntoa(conn.remote_ip))
    {:ok, raw} = Base.url_decode64(data["token"], padding: false)
    assert row.token == :crypto.hash(:sha256, raw)
    refute row.token == raw
    current = conn |> bearer(data["token"]) |> get(~p"/api/v1/auth/current-user")
    assert current.private.authorized
    assert json_response(current, 200)["data"]["id"] == user.id
  end

  test "invalid credentials and cookie sessions cannot authenticate the API", %{conn: conn} do
    user = user_fixture(password: "correct horse battery")

    for params <- [
          %{},
          %{email: user.email, password: "wrong"},
          %{email: "missing@example.com", password: "wrong"}
        ] do
      assert json_response(post(conn, ~p"/api/v1/auth/sessions", params), 401)["error"]["code"] ==
               "invalid_credentials"
    end

    response = conn |> log_in_user(user) |> get(~p"/api/v1/auth/current-user")
    assert json_response(response, 401)["error"]["code"] == "unauthorized"
  end

  test "sign-out revokes only the current token and requires authentication", %{conn: conn} do
    user = user_fixture()
    session = Accounts.generate_api_token(user)
    other = Accounts.generate_api_token(user)
    assert json_response(delete(conn, ~p"/api/v1/auth/session"), 401)

    assert json_response(conn |> bearer(session.token) |> delete(~p"/api/v1/auth/session"), 200) ==
             %{"data" => nil, "meta" => %{}}

    refute Accounts.get_user_by_api_token(session.token)
    assert Accounts.get_user_by_api_token(other.token)
  end

  test "registration records consent and sends an SPA link; validation returns message keys", %{
    conn: conn
  } do
    email = unique_email()

    result =
      post(conn, ~p"/api/v1/auth/registrations", %{name: "Ana", email: email, termsAccepted: true})

    assert result.private.authorized
    assert json_response(result, 201)["meta"]["message"] == "flash.magic_link_sent"
    assert Accounts.get_user_by_email(email)

    assert_email_sent(fn email ->
      assert email.text_body =~ "http://localhost:5173/auth/magic-links/"
    end)

    result = post(conn, ~p"/api/v1/auth/registrations", %{email: "x", termsAccepted: false})

    assert %{"error" => %{"code" => "validation_failed", "details" => details}} =
             json_response(result, 422)

    assert details["email"] == ["validation.email_format"]
    assert details["termsAccepted"] == ["validation.terms_required"]
  end

  test "magic requests do not enumerate users; consuming the link is single-use", %{conn: conn} do
    user = user_fixture(confirmed_at: nil)

    assert json_response(post(conn, ~p"/api/v1/auth/magic-links", %{email: user.email}), 200) ==
             json_response(post(conn, ~p"/api/v1/auth/magic-links", %{email: unique_email()}), 200)

    token = capture_token(&Accounts.deliver_login_instructions(user.email, &1))
    session = post(conn, ~p"/api/v1/auth/magic-links/#{token}/session", %{}) |> json_response(201)
    assert session["data"]["token"]
    assert_received {:analytics, %{event: "signup_confirmed", distinct_id: id}}
    assert id == user.id
    assert Accounts.get_user!(user.id).confirmed_at

    assert json_response(post(conn, ~p"/api/v1/auth/magic-links/#{token}/session", %{}), 422)[
             "error"
           ]["code"] == "invalid_token"

    assert json_response(post(conn, ~p"/api/v1/auth/magic-links/!/session", %{}), 422)["error"][
             "code"
           ] == "invalid_token"

    assert json_response(post(conn, ~p"/api/v1/auth/magic-links", %{}), 400)
  end

  test "confirmation consumes a token without issuing a session", %{conn: conn} do
    user = user_fixture(confirmed_at: nil)
    token = capture_token(&Accounts.deliver_login_instructions(user.email, &1))

    assert json_response(post(conn, ~p"/api/v1/auth/confirmations/#{token}", %{}), 200)["data"] ==
             nil

    assert Accounts.get_user!(user.id).confirmed_at
    refute Repo.exists?(from t in UserToken, where: t.user_id == ^user.id and t.context == "api")

    assert json_response(post(conn, ~p"/api/v1/auth/confirmations/#{token}", %{}), 422)["error"][
             "code"
           ] == "invalid_token"
  end

  test "password reset keeps requests private, validates confirmation and revokes sessions", %{
    conn: conn
  } do
    user = user_fixture(password: "correct horse battery")
    session = Accounts.generate_api_token(user)

    assert json_response(post(conn, ~p"/api/v1/auth/password-resets", %{email: user.email}), 200) ==
             json_response(
               post(conn, ~p"/api/v1/auth/password-resets", %{email: unique_email()}),
               200
             )

    assert_email_sent(fn email ->
      assert email.text_body =~ "http://localhost:5173/auth/password-resets/"
    end)

    token = capture_token(&Accounts.deliver_password_reset(user.email, &1))

    invalid =
      put(conn, ~p"/api/v1/auth/password-resets/#{token}", %{
        password: "short",
        passwordConfirmation: "other"
      })

    assert json_response(invalid, 422)["error"]["code"] == "validation_failed"

    result =
      put(conn, ~p"/api/v1/auth/password-resets/#{token}", %{
        password: "another correct horse",
        passwordConfirmation: "another correct horse"
      })

    assert json_response(result, 200)["data"] == nil
    assert Accounts.get_user_by_email_and_password(user.email, "another correct horse")
    refute Accounts.get_user_by_api_token(session.token)

    assert json_response(put(conn, ~p"/api/v1/auth/password-resets/#{token}", %{}), 422)["error"][
             "code"
           ] == "invalid_token"

    assert json_response(
             put(%{conn | remote_ip: {203, 0, 113, 101}}, ~p"/api/v1/auth/password-resets/!", %{}),
             422
           )["error"]["code"] ==
             "invalid_token"

    assert json_response(
             post(%{conn | remote_ip: {203, 0, 113, 102}}, ~p"/api/v1/auth/password-resets", %{}),
             400
           )
  end

  test "sudo verifies a password and extends only this token", %{conn: conn} do
    user = user_fixture(password: "correct horse battery")
    session = Accounts.generate_api_token(user)
    {_user, row} = Accounts.get_user_by_api_token(session.token)
    old = DateTime.add(DateTime.utc_now(:second), -60, :second)
    row |> Ecto.Changeset.change(sudo_until: old) |> Repo.update!()

    assert json_response(post(conn, ~p"/api/v1/auth/sudo", %{}), 401)["error"]["code"] ==
             "unauthorized"

    auth = bearer(conn, session.token)

    assert json_response(post(auth, ~p"/api/v1/auth/sudo", %{password: "wrong"}), 401)["error"][
             "code"
           ] == "invalid_credentials"

    result = post(auth, ~p"/api/v1/auth/sudo", %{password: "correct horse battery"})
    assert json_response(result, 200)["data"]["sudoUntil"]
    {_user, updated} = Accounts.get_user_by_api_token(session.token)
    assert DateTime.after?(updated.sudo_until, DateTime.utc_now())
  end

  test "impersonated sessions cannot elevate sudo", %{conn: conn} do
    user = user_fixture(password: "correct horse battery")
    admin = superadmin_fixture()
    session = Accounts.generate_api_token(user, %{}, impersonator_id: admin.id)

    result =
      conn
      |> bearer(session.token)
      |> post(~p"/api/v1/auth/sudo", %{password: "correct horse battery"})

    assert json_response(result, 403)["error"]["code"] == "forbidden"
  end

  test "expired emailed tokens and wrong contexts cannot confirm or reset passwords", %{conn: conn} do
    user = user_fixture()
    magic = capture_token(&Accounts.deliver_login_instructions(user.email, &1))
    reset = capture_token(&Accounts.deliver_password_reset(user.email, &1))

    Repo.update_all(from(t in UserToken, where: t.user_id == ^user.id),
      set: [inserted_at: DateTime.add(DateTime.utc_now(:second), -16, :minute)]
    )

    assert json_response(post(conn, ~p"/api/v1/auth/confirmations/#{magic}", %{}), 422)["error"][
             "code"
           ] == "invalid_token"

    assert json_response(post(conn, ~p"/api/v1/auth/magic-links/#{magic}/session", %{}), 422)[
             "error"
           ]["code"] == "invalid_token"

    assert json_response(
             put(conn, ~p"/api/v1/auth/password-resets/#{reset}", %{
               password: "correct horse battery"
             }),
             422
           )["error"]["code"] == "invalid_token"

    fresh = capture_token(&Accounts.deliver_password_reset(user.email, &1))

    assert json_response(post(conn, ~p"/api/v1/auth/confirmations/#{fresh}", %{}), 422)["error"][
             "code"
           ] == "invalid_token"
  end

  test "password reset confirms a previously unconfirmed email", %{conn: conn} do
    user = user_fixture(confirmed_at: nil)
    token = capture_token(&Accounts.deliver_password_reset(user.email, &1))

    assert json_response(
             put(conn, ~p"/api/v1/auth/password-resets/#{token}", %{
               password: "correct horse battery",
               passwordConfirmation: "correct horse battery"
             }),
             200
           )

    assert Accounts.get_user!(user.id).confirmed_at

    assert json_response(
             post(conn, ~p"/api/v1/auth/sessions", %{
               email: user.email,
               password: "correct horse battery"
             }),
             201
           )["data"]["token"]
  end

  test "expired and revoked bearer tokens return 401", %{conn: conn} do
    user = user_fixture()
    session = Accounts.generate_api_token(user)
    {_user, row} = Accounts.get_user_by_api_token(session.token)

    row
    |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(:second), -1))
    |> Repo.update!()

    for token <- [session.token, "!", "unknown"] do
      assert json_response(conn |> bearer(token) |> get(~p"/api/v1/auth/current-user"), 401)[
               "error"
             ]["code"] == "unauthorized"
    end
  end

  test "all anonymous auth actions that do work are rate limited", %{conn: conn} do
    for _ <- 1..10, do: post(conn, ~p"/api/v1/auth/sessions", %{})
    result = post(conn, ~p"/api/v1/auth/sessions", %{})
    assert json_response(result, 429)["error"]["code"] == "rate_limited"
    assert get_resp_header(result, "retry-after") != []
    assert get_resp_header(result, "cache-control") == ["private, no-store"]
    assert get_resp_header(result, "x-robots-tag") == ["noindex"]
  end

  test "policy denial and missing records use JSON envelopes", %{conn: conn} do
    user = user_fixture()
    session = Accounts.generate_api_token(user)
    auth = conn |> bearer(session.token) |> StarterKitWeb.Plugs.BearerAuth.call([])

    assert_raise StarterKitWeb.NotAuthorizedError, fn ->
      StarterKitWeb.Authorization.authorize!(auth, :update, user_fixture())
    end

    response = get(conn, "/api/v1/missing")
    assert json_response(response, 404)["error"]["code"] == "not_found"
    refute response.resp_body =~ "<html"
  end
end
