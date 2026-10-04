defmodule StarterKitWeb.ApiAuthTest do
  use StarterKitWeb.ConnCase, async: true
  import Ecto.Query
  import StarterKitWeb.ApiHelpers
  alias StarterKit.{Accounts, Audit, Repo}
  alias StarterKit.Accounts.{Impersonation, Session, UserToken}

  setup %{conn: conn}, do: %{conn: api_conn(conn)}

  test "bootstrap is anonymous, localized, never cached and cookie-free", %{conn: conn} do
    response =
      conn |> put_req_header("accept-language", "es-AR,en;q=0.5") |> get(~p"/api/v1/bootstrap")

    data = json_response(response, 200)["data"]
    assert data["auth"] == nil
    assert data["locale"] == "es"
    assert data["locales"] == ["en", "es"]
    assert data["app"]["publicUrl"] == "http://localhost:5173"
    assert data["app"]["signupMode"] == "open"
    assert get_resp_header(response, "set-cookie") == []
    assert get_resp_header(response, "cache-control") == ["private, no-store"]
    refute response.resp_body =~ "hashedPassword"
    refute response.resp_body =~ "fixture-secret"
    assert json_response(get(conn, ~p"/api/v1/bootstrap?locale=en"), 200)["data"]["locale"] == "en"
  end

  test "bootstrap Auth has the current tenant, sudo, session and only accessible organizations", %{
    conn: conn
  } do
    user = user_fixture(password: "correct horse battery", locale: "es")
    other = scope_fixture()
    session = sign_in(conn, user)
    auth_conn = bearer(conn, session["token"])
    auth = current_auth(auth_conn)
    assert auth["user"]["id"] == user.id
    assert auth["membership"]["user"] == nil
    assert auth["membership"]["role"] == "owner"
    assert auth["onboardingRequired"]
    assert auth["sudoUntil"]
    assert auth["sessionId"]
    refute auth["superadmin"]
    refute Enum.any?(auth["organizations"], &(&1["id"] == other.organization.id))
    assert json_response(get(auth_conn, ~p"/api/v1/bootstrap"), 200)["data"]["locale"] == "es"

    assert json_response(get(auth_conn, ~p"/api/v1/bootstrap?locale=en"), 200)["data"]["locale"] ==
             "en"
  end

  test "locale dictionary preserves keys, includes version metadata and revalidates", %{conn: conn} do
    response = get(conn, ~p"/api/v1/locales/es")
    body = json_response(response, 200)
    assert body["data"]["auth.session.title"]
    assert body["meta"]["locale"] == "es"
    assert body["meta"]["version"]
    assert get_resp_header(response, "cache-control") == ["public, no-cache"]
    [etag] = get_resp_header(response, "etag")
    assert etag == ~s("es:#{body["meta"]["version"]}")
    cached = conn |> put_req_header("if-none-match", etag) |> get(~p"/api/v1/locales/es")
    assert response(cached, 304) == ""
    assert_error(get(conn, ~p"/api/v1/locales/xx"), 404, "not_found")
  end

  test "password sessions return AuthSession and store a digest with device data", %{conn: conn} do
    user = user_fixture(password: "correct horse battery")
    session = sign_in(put_req_header(conn, "user-agent", "TestBrowser"), user)
    assert String.length(session["token"]) == 43
    assert session["newAccount"] == false
    assert session["impersonator"] == nil
    assert session["sudoUntil"]
    row = Repo.get_by!(Session, token_hash: :crypto.hash(:sha256, session["token"]))
    assert row.user_agent == "TestBrowser"
    assert row.ip_address == to_string(:inet.ntoa(conn.remote_ip))
    assert row.organization_id
    refute row.token_hash == session["token"]
    auth = bearer(conn, session["token"])
    second = sign_in(auth, user)
    assert second["token"] == nil
    assert Repo.aggregate(Session, :count) == 1
    assert current_auth(auth)["sessionId"] == row.id
  end

  test "password failures do not disclose whether the email exists; cookie sessions are ignored", %{
    conn: conn
  } do
    user = user_fixture(password: "correct horse battery")

    for params <- [
          %{},
          %{email: user.email, password: "wrong"},
          %{email: unique_email(), password: "wrong"}
        ] do
      assert_error(post(conn, ~p"/api/v1/auth/sessions", params), 401, "invalid_credentials")
    end

    assert_error(conn |> log_in_user(user) |> delete(~p"/api/v1/auth/session"), 401, "unauthorized")
    unconfirmed = user_fixture(password: "correct horse battery", confirmed_at: nil)

    assert_error(
      post(conn, ~p"/api/v1/auth/sessions", %{
        email: unconfirmed.email,
        password: "correct horse battery"
      }),
      401,
      "invalid_credentials"
    )
  end

  test "registration responds 202, emails a link and translates rich validation errors", %{
    conn: conn
  } do
    email = unique_email()

    response =
      post(
        conn,
        ~p"/api/v1/auth/registrations",
        Jason.encode!(%{name: "Ana", email: email, termsAccepted: "true"})
      )

    assert json_response(response, 202)["data"] == %{"email" => email, "newAccount" => true}
    token = email_token("/magic-links/")

    assert json_response(get(conn, ~p"/api/v1/auth/magic-links/#{token}"), 200)["data"] == %{
             "email" => email,
             "confirmed" => false
           }

    refute Accounts.get_user_by_email(email).confirmed_at

    invalid =
      conn
      |> put_req_header("accept-language", "es")
      |> post(~p"/api/v1/auth/registrations", %{email: "x", termsAccepted: false})

    assert_field(invalid, "name", "validation.required")
    assert_field(invalid, "email", "validation.email_format")
    assert_field(invalid, "termsAccepted", "validation.terms_required")

    duplicate =
      post(conn, ~p"/api/v1/auth/registrations", %{name: "Ana", email: email, termsAccepted: true})

    assert_field(duplicate, "email", "validation.unique")
  end

  test "magic requests always return 202 without disclosing account existence", %{conn: conn} do
    for email <- [user_fixture().email, unique_email()] do
      response = post(conn, ~p"/api/v1/auth/magic-links", %{email: email})
      assert json_response(response, 202)["data"] == %{"email" => email, "newAccount" => false}
    end

    for params <- [%{}, %{email: 3}],
        do: assert_error(post(conn, ~p"/api/v1/auth/magic-links", params), 400, "bad_request")
  end

  test "magic peek never consumes; first confirmation consumes all other links and is single use",
       %{conn: conn} do
    user = user_fixture(confirmed_at: nil)
    token = request_magic(conn, user.email)
    other = request_magic(conn, user.email)
    for _ <- 1..2, do: assert(json_response(get(conn, ~p"/api/v1/auth/magic-links/#{token}"), 200))

    session =
      post(conn, ~p"/api/v1/auth/magic-links/#{token}/session", %{})
      |> json_response(201)
      |> Map.fetch!("data")

    assert session["newAccount"]
    assert session["token"]
    assert session["sudoUntil"]
    assert session["user"]["confirmedAt"]
    assert_received {:analytics, %{event: "signup_confirmed", distinct_id: id}}
    assert id == user.id

    for spent <- [token, other, "!"] do
      assert_error(get(conn, ~p"/api/v1/auth/magic-links/#{spent}"), 422, "magic_link_invalid")

      assert_error(
        post(conn, ~p"/api/v1/auth/magic-links/#{spent}/session", %{}),
        422,
        "magic_link_invalid"
      )
    end
  end

  test "magic login for the same signed-in user refreshes sudo without a new token", %{conn: conn} do
    user = user_fixture(password: "correct horse battery")
    session = sign_in(conn, user)
    token = request_magic(conn, user.email)
    auth = bearer(conn, session["token"])
    response = post(auth, ~p"/api/v1/auth/magic-links/#{token}/session", %{}) |> json_response(201)
    assert response["data"]["token"] == nil
    refute response["data"]["newAccount"]
    assert Repo.aggregate(Session, :count) == 1
  end

  test "expired and wrong-context magic links fail both peek and consume", %{conn: conn} do
    user = user_fixture()
    token = request_magic(conn, user.email)

    Repo.update_all(from(t in UserToken, where: t.user_id == ^user.id),
      set: [inserted_at: DateTime.add(DateTime.utc_now(:second), -16, :minute)]
    )

    assert_error(get(conn, ~p"/api/v1/auth/magic-links/#{token}"), 422, "magic_link_invalid")

    assert_error(
      post(conn, ~p"/api/v1/auth/magic-links/#{token}/session", %{}),
      422,
      "magic_link_invalid"
    )
  end

  test "sudo supports password and same-user magic tokens, never another user's token", %{
    conn: conn
  } do
    user = user_fixture(password: "correct horse battery")
    session = sign_in(conn, user)
    auth = bearer(conn, session["token"])
    assert_error(post(conn, ~p"/api/v1/auth/sudo", %{}), 401, "unauthorized")

    assert_error(
      post(auth, ~p"/api/v1/auth/sudo", %{password: "wrong"}),
      401,
      "invalid_credentials"
    )

    assert json_response(
             post(auth, ~p"/api/v1/auth/sudo", %{password: "correct horse battery"}),
             200
           )["data"]["sudoUntil"]

    assert Repo.aggregate(
             from(a in Audit.AuditEvent, where: a.action == "user.sudo_authenticated"),
             :count
           ) == 1

    wrong = request_magic(conn, user_fixture().email)

    assert_error(
      post(auth, ~p"/api/v1/auth/sudo", %{magicLinkToken: wrong}),
      422,
      "magic_link_invalid"
    )

    token = request_magic(conn, user.email)

    assert json_response(post(auth, ~p"/api/v1/auth/sudo", %{magicLinkToken: token}), 200)["data"][
             "sudoUntil"
           ]

    assert_error(
      post(auth, ~p"/api/v1/auth/sudo", %{magicLinkToken: token}),
      422,
      "magic_link_invalid"
    )
  end

  test "a passwordless user can elevate only with their magic link", %{conn: conn} do
    user = user_fixture()
    token = request_magic(conn, user.email)
    session = post(conn, ~p"/api/v1/auth/magic-links/#{token}/session", %{}) |> json_response(201)
    auth = bearer(conn, session["data"]["token"])

    assert_field(
      post(auth, ~p"/api/v1/auth/sudo", %{password: "anything"}),
      "password",
      "validation.required"
    )

    token = request_magic(conn, user.email)
    assert json_response(post(auth, ~p"/api/v1/auth/sudo", %{magicLinkToken: token}), 200)
  end

  test "sign-out is 204, preserves other devices and known revoked tokens are expired", %{
    conn: conn
  } do
    user = user_fixture(password: "correct horse battery")
    one = sign_in(conn, user)
    other = sign_in(conn, user)
    auth = bearer(conn, one["token"])
    assert_error(delete(conn, ~p"/api/v1/auth/session"), 401, "unauthorized")
    assert response(delete(auth, ~p"/api/v1/auth/session"), 204) == ""
    assert_error(get(auth, ~p"/api/v1/bootstrap"), 401, "session_expired")
    assert current_auth(bearer(conn, other["token"]))["user"]["id"] == user.id
    assert_error(bearer(conn, "unknown") |> delete(~p"/api/v1/auth/session"), 401, "unauthorized")
  end

  test "session expiry slides under seven days and last-used updates are bounded", %{conn: conn} do
    user = user_fixture(password: "correct horse battery")
    session = sign_in(conn, user)
    row = Repo.get_by!(Session, token_hash: :crypto.hash(:sha256, session["token"]))
    timestamp = DateTime.utc_now(:second)

    row
    |> Ecto.Changeset.change(expires_at: DateTime.add(timestamp, 6, :day), last_used_at: timestamp)
    |> Repo.update!()

    auth = bearer(conn, session["token"])
    assert current_auth(auth)
    updated = Repo.reload!(row)
    assert DateTime.diff(updated.expires_at, timestamp, :day) == 14
    assert current_auth(auth)
    assert Repo.reload!(row).last_used_at == updated.last_used_at
    row |> Ecto.Changeset.change(expires_at: DateTime.add(timestamp, -1)) |> Repo.update!()
    assert_error(get(auth, ~p"/api/v1/bootstrap"), 401, "session_expired")
  end

  test "impersonation stop preserves admin; sign-out revokes both; impersonation has no sudo", %{
    conn: conn
  } do
    admin = superadmin_fixture()
    admin_session = Accounts.generate_api_token(admin)
    target = user_fixture(password: "correct horse battery")

    {:ok, imp} =
      Accounts.start_impersonation(Accounts.Scope.for_user(admin), target, %{reason: "Support"})

    opts = [
      impersonator_user_id: admin.id,
      impersonator_session_id: admin_session.session.id,
      impersonation_id: imp.id
    ]

    impersonation = Accounts.generate_api_token(target, %{}, opts)
    assert DateTime.diff(impersonation.expires_at, impersonation.session.inserted_at) == 8 * 60 * 60
    auth = bearer(conn, impersonation.token)
    bootstrap = current_auth(auth)
    assert Repo.get!(Session, impersonation.session.id).expires_at == impersonation.expires_at
    refute bootstrap["superadmin"]
    assert bootstrap["impersonator"]["id"] == admin.id
    assert bootstrap["sudoUntil"] == nil

    assert_error(
      post(auth, ~p"/api/v1/auth/sudo", %{password: "correct horse battery"}),
      403,
      "forbidden"
    )

    assert response(delete(auth, ~p"/api/v1/auth/impersonation"), 204) == ""
    assert Repo.get!(Impersonation, imp.id).ended_at
    assert current_auth(bearer(conn, admin_session.token))["superadmin"]
    assert_error(get(auth, ~p"/api/v1/bootstrap"), 401, "session_expired")

    assert_error(
      delete(bearer(conn, admin_session.token), ~p"/api/v1/auth/impersonation"),
      409,
      "conflict"
    )

    assert_error(delete(conn, ~p"/api/v1/auth/impersonation"), 401, "unauthorized")
    next = Accounts.generate_api_token(target, %{}, opts)
    assert response(delete(bearer(conn, next.token), ~p"/api/v1/auth/session"), 204) == ""

    assert_error(
      get(bearer(conn, admin_session.token), ~p"/api/v1/bootstrap"),
      401,
      "session_expired"
    )
  end

  test "auth rate limits include Retry-After and structured details", %{conn: conn} do
    for {path, count} <- [
          {"/api/v1/auth/sessions", 10},
          {"/api/v1/auth/registrations", 10},
          {"/api/v1/auth/magic-links", 5},
          {"/api/v1/auth/magic-links/!/session", 10}
        ] do
      for _ <- 1..count, do: post(conn, path, %{})
      response = post(conn, path, %{})
      details = assert_error(response, 429, "rate_limited")
      assert get_resp_header(response, "retry-after") == [to_string(details["retryAfter"])]
    end

    user = user_fixture(password: "correct horse battery")
    auth = bearer(api_conn(conn), sign_in(api_conn(conn), user)["token"])
    for _ <- 1..5, do: post(auth, ~p"/api/v1/auth/sudo", %{password: "wrong"})
    assert_error(post(auth, ~p"/api/v1/auth/sudo", %{password: "wrong"}), 429, "rate_limited")
  end

  test "unsupported methods, media types, malformed JSON and missing paths use envelopes", %{
    conn: conn
  } do
    assert_error(patch(conn, ~p"/api/v1/auth/sessions", %{}), 405, "method_not_allowed")
    assert_error(get(conn, ~p"/api/v1/auth/sessions"), 405, "method_not_allowed")

    assert_error(
      conn
      |> put_req_header("content-type", "text/plain")
      |> post(~p"/api/v1/auth/sessions", "bad"),
      415,
      "bad_request"
    )

    assert_error(
      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/v1/auth/sessions", "{"),
      400,
      "invalid_json"
    )

    assert_error(get(conn, "/api/v1/missing"), 404, "not_found")

    for path <- [
          "/api/v1/auth/current-user",
          "/api/v1/auth/confirmations/token",
          "/api/v1/auth/password-resets"
        ],
        do: assert_error(get(conn, path), 404, "not_found")
  end

  test "registration rejects wrong JSON types and every valid name can establish a tenant", %{
    conn: conn
  } do
    assert_error(
      post(conn, ~p"/api/v1/auth/registrations", %{
        name: ["Ana"],
        email: unique_email(),
        termsAccepted: true
      }),
      400,
      "bad_request"
    )

    for name <- ["A", String.duplicate("a", 120)] do
      email = unique_email()

      assert json_response(
               post(conn, ~p"/api/v1/auth/registrations", %{
                 name: name,
                 email: email,
                 termsAccepted: true
               }),
               202
             )

      token = email_token("/magic-links/")
      result = post(conn, ~p"/api/v1/auth/magic-links/#{token}/session", %{}) |> json_response(201)
      assert current_auth(bearer(conn, result["data"]["token"]))["membership"]["role"] == "owner"
    end
  end

  test "sudo requires exactly one correctly typed proof", %{conn: conn} do
    user = user_fixture(password: "correct horse battery")
    auth = bearer(conn, sign_in(conn, user)["token"])

    for params <- [
          %{},
          %{password: 3},
          %{magicLinkToken: 3},
          %{password: "correct horse battery", magicLinkToken: "unused"}
        ] do
      assert_error(post(auth, ~p"/api/v1/auth/sudo", params), 400, "bad_request")
    end
  end

  test "revoking an administrator's session also revokes the impersonation it started", %{
    conn: conn
  } do
    admin = superadmin_fixture()
    original = Accounts.generate_api_token(admin)
    target = user_fixture()

    impersonation =
      Accounts.generate_api_token(target, %{},
        impersonator_user_id: admin.id,
        impersonator_session_id: original.session.id
      )

    auth = bearer(conn, impersonation.token)
    assert current_auth(auth)["impersonator"]["id"] == admin.id
    assert response(delete(bearer(conn, original.token), ~p"/api/v1/auth/session"), 204) == ""
    assert_error(get(auth, ~p"/api/v1/bootstrap"), 401, "session_expired")
  end

  test "daily purge removes only ended impersonations older than 90 days" do
    admin = superadmin_fixture()
    target = user_fixture()
    scope = Accounts.Scope.for_user(admin)
    {:ok, old} = Accounts.start_impersonation(scope, target, %{reason: "Old support"})
    {:ok, recent} = Accounts.start_impersonation(scope, target, %{reason: "Recent support"})
    {:ok, running} = Accounts.start_impersonation(scope, target, %{reason: "Running support"})

    Repo.update!(
      Ecto.Changeset.change(old, ended_at: DateTime.add(DateTime.utc_now(:second), -91, :day))
    )

    Repo.update!(
      Ecto.Changeset.change(recent, ended_at: DateTime.add(DateTime.utc_now(:second), -89, :day))
    )

    assert :ok = Accounts.purge_expired_tokens()
    refute Repo.get(Impersonation, old.id)
    assert Repo.get(Impersonation, recent.id)
    assert Repo.get(Impersonation, running.id)
  end
end
