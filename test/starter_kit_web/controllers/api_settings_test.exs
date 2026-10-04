defmodule StarterKitWeb.ApiSettingsTest do
  use StarterKitWeb.ConnCase, async: true
  import Ecto.Query
  import StarterKitWeb.ApiHelpers
  alias StarterKit.{Accounts, Audit, Organizations, Repo}
  alias StarterKit.Accounts.{Session, User, UserToken}

  setup %{conn: conn} do
    conn = api_conn(conn)
    user = user_fixture(password: "correct horse battery")
    session = sign_in(conn, user)
    %{conn: conn, user: user, session: session, auth: bearer(conn, session["token"])}
  end

  for {method, path} <- [
        {:put, "/api/v1/settings/profile"},
        {:get, "/api/v1/settings/email-preferences"},
        {:put, "/api/v1/settings/email-preferences"},
        {:get, "/api/v1/settings/sessions"},
        {:delete, "/api/v1/settings/sessions/unknown"},
        {:put, "/api/v1/settings/email"},
        {:get, "/api/v1/settings/email-confirmations/unknown"},
        {:post, "/api/v1/settings/email-confirmations"},
        {:put, "/api/v1/settings/password"},
        {:get, "/api/v1/settings/account"},
        {:delete, "/api/v1/settings/account"}
      ] do
    @method method
    @path path
    test "#{method} #{path} requires a bearer", %{conn: conn} do
      assert_error(settings_request(conn, @method, @path, %{}), 401, "unauthorized")
    end
  end

  for {method, path} <- [
        {:put, "/api/v1/settings/email"},
        {:put, "/api/v1/settings/password"},
        {:get, "/api/v1/settings/account"},
        {:delete, "/api/v1/settings/account"}
      ],
      state <- [:missing, :expired, :impersonation] do
    @method method
    @path path
    @state state
    test "#{method} #{path} refuses #{@state} sudo", %{conn: conn, user: user, session: session} do
      token = sudo_token(conn, user, session, @state)

      assert_error(settings_request(bearer(conn, token), @method, @path, %{}), 403, "sudo_required")
      assert Repo.get(User, user.id)
    end
  end

  test "profile updates only name and locale and returns User", %{auth: auth, user: user} do
    data =
      put(auth, ~p"/api/v1/settings/profile", %{
        name: "Ana",
        locale: "es",
        role: "superadmin",
        email: unique_email()
      })
      |> json_response(200)
      |> Map.fetch!("data")

    assert data["name"] == "Ana"
    assert data["locale"] == "es"
    assert data["email"] == user.email
    assert data["role"] == "user"
    assert data["hasPassword"]
    assert data["confirmedAt"] =~ ~r/Z$/
    assert Repo.reload!(user).locale == "es"
  end

  test "profile validates name and locale with translated field details", %{auth: auth, user: user} do
    error =
      assert_error(
        put(auth, ~p"/api/v1/settings/profile?locale=es", %{name: "", locale: "xx"}),
        422,
        "validation_failed"
      )

    assert [%{"key" => "validation.required", "message" => message}] = error["name"]
    assert message == StarterKit.I18n.t("validation.required", %{}, "es")
    assert [%{"key" => "validation.inclusion"}] = error["locale"]

    error =
      assert_error(
        put(auth, ~p"/api/v1/settings/profile", %{name: String.duplicate("a", 121)}),
        422,
        "validation_failed"
      )

    assert [%{"key" => "validation.length_max", "bindings" => %{"count" => 120}}] =
             error["name"]

    error =
      assert_error(
        put(auth, ~p"/api/v1/settings/profile", %{locale: nil}),
        422,
        "validation_failed"
      )

    assert [%{"key" => "validation.required"}] = error["locale"]
    assert Repo.reload!(user).name == user.name
  end

  test "profile refuses wrongly typed values", %{auth: auth} do
    assert_error(put(auth, ~p"/api/v1/settings/profile", %{name: []}), 400, "bad_request")
  end

  test "email preferences show the current value", %{auth: auth} do
    assert json_response(get(auth, ~p"/api/v1/settings/email-preferences"), 200)["data"] == %{
             "optionalEmails" => true
           }
  end

  test "email preferences accept booleans and audit only changes", %{auth: auth, user: user} do
    for value <- [false, false, "true"] do
      result =
        put(auth, ~p"/api/v1/settings/email-preferences", %{optionalEmails: value})
        |> json_response(200)

      assert result["data"]["optionalEmails"] == (value == "true")
    end

    assert Repo.reload!(user).optional_emails
    assert event_count("user.optional_emails_stopped", user.id) == 1
    assert event_count("user.optional_emails_started", user.id) == 1
  end

  test "email preferences require a boolean", %{auth: auth} do
    for params <- [%{}, %{optionalEmails: nil}] do
      error =
        assert_error(
          put(auth, ~p"/api/v1/settings/email-preferences", params),
          422,
          "validation_failed"
        )

      assert [%{"key" => "validation.required"}] = error["optionalEmails"]
    end

    assert_error(
      put(auth, ~p"/api/v1/settings/email-preferences", %{optionalEmails: "perhaps"}),
      400,
      "bad_request"
    )
  end

  test "devices include only this user's live ordinary sessions, newest first, marking current", %{
    auth: auth,
    user: user,
    session: session
  } do
    old = Accounts.generate_api_token(user, %{user_agent: "Older browser", ip_address: "1.2.3.4"})

    Repo.update!(
      Ecto.Changeset.change(old.session, inserted_at: DateTime.add(DateTime.utc_now(:second), -60))
    )

    expired = Accounts.generate_api_token(user)

    Repo.update!(
      Ecto.Changeset.change(expired.session,
        expires_at: DateTime.add(DateTime.utc_now(:second), -1)
      )
    )

    revoked = Accounts.generate_api_token(user)
    Repo.update!(Ecto.Changeset.change(revoked.session, revoked_at: DateTime.utc_now(:second)))
    Accounts.generate_api_token(user_fixture())
    Accounts.generate_api_token(user, %{}, impersonator_user_id: superadmin_fixture().id)
    response = get(auth, ~p"/api/v1/settings/sessions")
    [current, other] = json_response(response, 200)["data"]
    assert current["id"] == current_id(session)
    assert current["current"]
    assert other["id"] == old.session.id
    refute other["current"]
    assert other["userAgent"] == "Older browser"
    assert other["ipAddress"] == "1.2.3.4"
    assert other["authenticatedAt"] =~ ~r/Z$/
    refute response.resp_body =~ "token"
  end

  test "revoking another device audits and its token then expires", %{
    conn: conn,
    auth: auth,
    user: user
  } do
    other = Accounts.generate_api_token(user)
    assert response(delete(auth, ~p"/api/v1/settings/sessions/#{other.session.id}"), 204) == ""
    assert event_count("session.revoked", user.id) == 1

    assert_error(
      get(bearer(conn, other.token), ~p"/api/v1/settings/sessions"),
      401,
      "session_expired"
    )

    assert json_response(get(auth, ~p"/api/v1/settings/sessions"), 200)
  end

  test "revoking the caller's device is allowed", %{auth: auth, session: session} do
    assert response(delete(auth, ~p"/api/v1/settings/sessions/#{current_id(session)}"), 204) == ""
    assert_error(get(auth, ~p"/api/v1/settings/sessions"), 401, "session_expired")
  end

  test "a user's device cannot revoke another user's session or an unknown id", %{auth: auth} do
    other = Accounts.generate_api_token(user_fixture())

    for id <- [other.session.id, Ecto.UUID.generate(), "not-a-uuid"] do
      assert_error(delete(auth, ~p"/api/v1/settings/sessions/#{id}"), 404, "not_found")
    end

    refute Repo.reload!(other.session).revoked_at
  end

  test "email change sends the new address a localized SPA confirmation link", %{
    auth: auth,
    user: user
  } do
    assert json_response(put(auth, ~p"/api/v1/settings/profile", %{locale: "es"}), 200)
    email = unique_email()

    assert json_response(put(auth, ~p"/api/v1/settings/email", %{email: email}), 202)["data"] == %{
             "email" => email
           }

    assert_receive {:email, mail}
    assert mail.to == [{user.name, email}]

    assert mail.subject ==
             StarterKit.I18n.t("mail.email_change.subject", %{app: "StarterKit"}, "es")

    assert mail.text_body =~ "http://localhost:5173/settings/email-confirmations/"
    refute mail.text_body =~ "/api/v1/"
    assert Repo.reload!(user).email == user.email
    assert current_auth(auth)
  end

  test "email change validates missing, format, length and uniqueness", %{auth: auth, user: user} do
    other = user_fixture()

    for {params, key} <- [
          {%{}, "validation.required"},
          {%{email: "broken"}, "validation.email_format"},
          {%{email: String.duplicate("a", 150) <> "@example.com"}, "validation.length_max"},
          {%{email: other.email}, "validation.unique"}
        ] do
      error = assert_error(put(auth, ~p"/api/v1/settings/email", params), 422, "validation_failed")
      assert Enum.any?(error["email"], &(&1["key"] == key))
    end

    assert Repo.reload!(user).email == user.email
    assert Repo.aggregate(UserToken, :count) == 0
    refute_received {:email, _}
  end

  test "email change rejects the same address as a conflict and field error", %{
    auth: auth,
    user: user
  } do
    for email <- [user.email, String.upcase(user.email)] do
      error =
        assert_error(put(auth, ~p"/api/v1/settings/email", %{email: email}), 409, "email_unchanged")

      assert [%{"key" => "validation.email_unchanged", "message" => _}] = error["email"]
    end

    assert Repo.aggregate(UserToken, :count) == 0
  end

  test "email change refuses wrong types", %{auth: auth} do
    assert_error(put(auth, ~p"/api/v1/settings/email", %{email: []}), 400, "bad_request")
  end

  test "change email → peek → apply → sign in with new email", %{
    conn: conn,
    auth: auth,
    user: user,
    session: session
  } do
    first_email = unique_email()
    email = unique_email()
    assert json_response(put(auth, ~p"/api/v1/settings/email", %{email: first_email}), 202)
    first = email_token("/settings/email-confirmations/")
    assert json_response(put(auth, ~p"/api/v1/settings/email", %{email: email}), 202)
    token = email_token("/settings/email-confirmations/")
    # Retire sudo: the session plus emailed token is sufficient for peek and apply.
    Repo.update!(Ecto.Changeset.change(Repo.get!(Session, current_id(session)), sudo_until: nil))

    for _ <- 1..2 do
      assert json_response(get(auth, ~p"/api/v1/settings/email-confirmations/#{token}"), 200)[
               "data"
             ] == %{"email" => email}

      assert Repo.reload!(user).email == user.email
    end

    magic = request_magic(conn, user.email)
    # Also remove historical change contexts, but preserve unrelated magic links.
    Repo.insert!(%UserToken{
      user_id: user.id,
      context: "change_email:old@example.com",
      token: :crypto.strong_rand_bytes(32),
      sent_to: first_email
    })

    changed =
      post(auth, ~p"/api/v1/settings/email-confirmations", %{token: token}) |> json_response(200)

    assert changed["data"]["email"] == email
    assert changed["data"]["id"] == user.id
    assert event_count("user.email_changed", user.id) == 1

    refute Repo.exists?(
             from t in UserToken, where: t.user_id == ^user.id and like(t.context, "change_email:%")
           )

    assert Repo.exists?(
             from t in UserToken, where: t.user_id == ^user.id and t.context == "magic_link"
           )

    assert_error(get(conn, ~p"/api/v1/auth/magic-links/#{magic}"), 422, "magic_link_invalid")

    for spent <- [token, first] do
      assert_error(
        get(auth, ~p"/api/v1/settings/email-confirmations/#{spent}"),
        422,
        "email_change_invalid"
      )

      assert_error(
        post(auth, ~p"/api/v1/settings/email-confirmations", %{token: spent}),
        422,
        "email_change_invalid"
      )
    end

    assert_error(
      post(conn, ~p"/api/v1/auth/sessions", %{email: user.email, password: "correct horse battery"}),
      401,
      "invalid_credentials"
    )

    assert sign_in(conn, %{user | email: email})["user"]["email"] == email
  end

  for method <- [:get, :post], outcome <- [:unknown, :expired, :another_user] do
    @method method
    @outcome outcome
    test "email confirmation #{method} refuses #{outcome} tokens", %{
      conn: conn,
      auth: auth,
      user: user
    } do
      token = confirmation_token(conn, auth, user, @outcome)

      result =
        if @method == :get,
          do: get(auth, ~p"/api/v1/settings/email-confirmations/#{token}"),
          else: post(auth, ~p"/api/v1/settings/email-confirmations", %{token: token})

      assert_error(result, 422, "email_change_invalid")
      assert Repo.reload!(user).email == user.email
      if @outcome == :another_user, do: assert(Repo.aggregate(UserToken, :count) == 1)
    end
  end

  test "email confirmation apply rejects absent and incorrectly typed tokens", %{auth: auth} do
    for params <- [%{}, %{token: nil}, %{token: []}] do
      assert_error(
        post(auth, ~p"/api/v1/settings/email-confirmations", params),
        422,
        "email_change_invalid"
      )
    end
  end

  test "email confirmation refuses an address claimed after the request", %{auth: auth, user: user} do
    email = unique_email()
    assert json_response(put(auth, ~p"/api/v1/settings/email", %{email: email}), 202)
    token = email_token("/settings/email-confirmations/")
    user_fixture(email: email)

    assert_error(
      post(auth, ~p"/api/v1/settings/email-confirmations", %{token: token}),
      422,
      "email_change_invalid"
    )

    assert Repo.reload!(user).email == user.email
    assert Repo.aggregate(UserToken, :count) == 1
  end

  test "password validates byte length, confirmation and required fields without revoking", %{
    auth: auth,
    session: session
  } do
    for {password, confirmation, field, key} <- [
          {nil, nil, "password", "validation.required"},
          {"short", "short", "password", "validation.length_min"},
          {String.duplicate("a", 73), String.duplicate("a", 73), "password",
           "validation.length_max"},
          {String.duplicate("é", 37), String.duplicate("é", 37), "password",
           "validation.length_max"},
          {"new password value", "different value", "passwordConfirmation",
           "validation.password_mismatch"},
          {"new password value", nil, "passwordConfirmation", "validation.password_mismatch"}
        ] do
      params = %{password: password, passwordConfirmation: confirmation}

      error =
        assert_error(put(auth, ~p"/api/v1/settings/password", params), 422, "validation_failed")

      assert Enum.any?(error[field], &(&1["key"] == key))

      if key == "validation.length_min",
        do: assert(hd(error[field])["bindings"] == %{"count" => 12})

      refute Repo.get!(Session, current_id(session)).revoked_at
    end

    error =
      assert_error(
        put(auth, ~p"/api/v1/settings/password", %{password: "new password value"}),
        422,
        "validation_failed"
      )

    assert [%{"key" => "validation.password_mismatch"}] = error["passwordConfirmation"]
    assert_error(put(auth, ~p"/api/v1/settings/password", %{password: []}), 400, "bad_request")
  end

  test "set password → other sessions revoked → old token 401", %{conn: conn} do
    user = user_fixture()
    magic = request_magic(conn, user.email)

    first =
      post(conn, ~p"/api/v1/auth/magic-links/#{magic}/session", %{})
      |> json_response(201)
      |> Map.fetch!("data")

    other = Accounts.generate_api_token(user)
    unused = request_magic(conn, user.email)
    auth = bearer(conn, first["token"]) |> put_req_header("user-agent", "Current browser")
    password = String.duplicate("é", 6)

    fresh =
      put(auth, ~p"/api/v1/settings/password", %{password: password, passwordConfirmation: password})
      |> json_response(200)
      |> Map.fetch!("data")

    assert byte_size(fresh["token"]) == 43
    assert fresh["token"] != first["token"]
    assert fresh["user"]["hasPassword"]
    assert fresh["sudoUntil"]
    assert fresh["expiresAt"]
    assert fresh["impersonator"] == nil
    refute fresh["newAccount"]
    assert event_count("user.password_changed", user.id) == 1

    for token <- [first["token"], other.token] do
      assert_error(get(bearer(conn, token), ~p"/api/v1/settings/sessions"), 401, "session_expired")
    end

    assert_error(get(conn, ~p"/api/v1/auth/magic-links/#{unused}"), 422, "magic_link_invalid")
    assert Repo.aggregate(UserToken, :count) == 0

    [device] =
      json_response(get(bearer(conn, fresh["token"]), ~p"/api/v1/settings/sessions"), 200)["data"]

    assert device["current"]
    assert device["userAgent"] == "Current browser"
    assert device["ipAddress"]
    assert sign_in(conn, user, password)["user"]["id"] == user.id
  end

  test "changing a password invalidates the old password and accepts 72 bytes", %{
    conn: conn,
    auth: auth,
    user: user
  } do
    password = String.duplicate("a", 72)

    assert json_response(
             put(auth, ~p"/api/v1/settings/password", %{
               password: password,
               passwordConfirmation: password
             }),
             200
           )["data"]["token"]

    assert_error(
      post(conn, ~p"/api/v1/auth/sessions", %{email: user.email, password: "correct horse battery"}),
      401,
      "invalid_credentials"
    )

    assert sign_in(conn, user, password)["token"]
  end

  test "password rotation also revokes impersonations started by the old admin session", %{
    conn: conn
  } do
    admin = superadmin_fixture(password: "correct horse battery")
    original = sign_in(conn, admin)

    child =
      Accounts.generate_api_token(user_fixture(), %{},
        impersonator_user_id: admin.id,
        impersonator_session_id: current_id(original)
      )

    password = "another safe password"

    assert json_response(
             put(bearer(conn, original["token"]), ~p"/api/v1/settings/password", %{
               password: password,
               passwordConfirmation: password
             }),
             200
           )

    assert_error(
      get(bearer(conn, child.token), ~p"/api/v1/settings/sessions"),
      401,
      "session_expired"
    )
  end

  test "account preview has no blocker for a lone owner", %{auth: auth} do
    assert json_response(get(auth, ~p"/api/v1/settings/account"), 200)["data"] == %{
             "blocker" => nil
           }
  end

  test "last owner deletion is blocked, then ownership transfer allows deletion", %{
    conn: conn,
    auth: auth,
    user: user,
    session: session
  } do
    scope = scope_fixture(user)
    member = user_fixture()
    membership = membership_fixture(scope, member)
    preview = json_response(get(auth, ~p"/api/v1/settings/account"), 200)["data"]

    assert preview["blocker"] == %{
             "reason" => "transfer_ownership",
             "organization" => scope.organization.name
           }

    error = assert_error(delete(auth, ~p"/api/v1/settings/account"), 409, "transfer_ownership")
    assert error == %{"organization" => scope.organization.name}
    assert Repo.get(User, user.id)
    assert Repo.get!(Session, current_id(session)).revoked_at == nil
    assert event_count("user.deleted", user.id) == 0

    assert json_response(
             put(auth, ~p"/api/v1/settings/members/#{membership.id}", %{
               role: "owner",
               access: "full"
             }),
             200
           )

    assert json_response(get(auth, ~p"/api/v1/settings/account"), 200)["data"]["blocker"] == nil
    assert response(delete(auth, ~p"/api/v1/settings/account"), 204) == ""
    refute Repo.get(User, user.id)
    assert Repo.get(Organizations.Organization, scope.organization.id)
    assert event_count("user.deleted", user.id) == 1

    assert_error(
      get(bearer(conn, session["token"]), ~p"/api/v1/settings/sessions"),
      401,
      "unauthorized"
    )
  end

  test "deletion re-checks blockers appearing after a clear preview", %{auth: auth, user: user} do
    assert json_response(get(auth, ~p"/api/v1/settings/account"), 200)["data"]["blocker"] == nil
    scope = scope_fixture(user)
    membership_fixture(scope, user_fixture())
    assert_error(delete(auth, ~p"/api/v1/settings/account"), 409, "transfer_ownership")
    assert Repo.get(User, user.id)
  end

  test "an open subscription blocks deletion with details, even when billing is off", %{
    auth: auth,
    user: user
  } do
    scope = scope_fixture(user)
    subscription_fixture(scope, %{status: "past_due"})

    assert json_response(get(auth, ~p"/api/v1/settings/account"), 200)["data"]["blocker"] == %{
             "reason" => "subscription_active",
             "organization" => scope.organization.name
           }

    error = assert_error(delete(auth, ~p"/api/v1/settings/account"), 409, "subscription_active")
    assert error == %{"organization" => scope.organization.name}
    assert Repo.get(User, user.id)
    assert Repo.get(Organizations.Organization, scope.organization.id)
    assert event_count("user.deleted", user.id) == 0
  end

  test "deletion preserves ended billing history", %{auth: auth, user: user} do
    scope = scope_fixture(user)
    subscription_fixture(scope, %{status: "canceled"})
    assert response(delete(auth, ~p"/api/v1/settings/account"), 204) == ""
    refute Repo.get(User, user.id)
    assert Repo.get(Organizations.Organization, scope.organization.id)
  end

  test "deletion removes empty organizations, sessions and tokens, preserves consent and audits", %{
    conn: conn
  } do
    email = unique_email()
    terms = published_legal_fixture("terms")
    privacy = published_legal_fixture("privacy")

    assert json_response(
             post(conn, ~p"/api/v1/auth/registrations", %{
               name: "Ana",
               email: email,
               termsAccepted: true
             }),
             202
           )

    token = email_token("/magic-links/")

    session =
      post(conn, ~p"/api/v1/auth/magic-links/#{token}/session", %{})
      |> json_response(201)
      |> Map.fetch!("data")

    user = Accounts.get_user_by_email(email)
    auth = bearer(conn, session["token"])
    org_id = current_auth(auth)["organization"]["id"]
    request_magic(conn, email)
    other = Accounts.generate_api_token(user)
    assert response(delete(auth, ~p"/api/v1/settings/account"), 204) == ""
    refute Repo.get(User, user.id)
    refute Repo.get(Organizations.Organization, org_id)
    refute Repo.exists?(from s in Session, where: s.user_id == ^user.id)
    refute Repo.exists?(from t in UserToken, where: t.user_id == ^user.id)

    for version <- [terms, privacy] do
      acceptance =
        Repo.get_by!(StarterKit.Legal.LegalAcceptance, legal_document_version_id: version.id)

      assert acceptance.user_id == nil
      assert acceptance.subject_email_hash
    end

    assert event_count("user.deleted", user.id) == 1
    assert event_count("organization.deleted", user.id) == 1
    assert_error(get(bearer(conn, other.token), ~p"/api/v1/settings/sessions"), 401, "unauthorized")
  end

  test "email changes are limited per user across devices and IPs", %{
    conn: conn,
    auth: auth,
    user: user
  } do
    for _ <- 1..5,
        do: assert_error(put(auth, ~p"/api/v1/settings/email", %{}), 422, "validation_failed")

    other_device = bearer(api_conn(conn), Accounts.generate_api_token(user).token)
    result = put(other_device, ~p"/api/v1/settings/email", %{})
    assert_error(result, 429, "rate_limited")
    assert get_resp_header(result, "retry-after") != []
    other_user = user_fixture(password: "correct horse battery")

    assert_error(
      put(bearer(conn, sign_in(conn, other_user)["token"]), ~p"/api/v1/settings/email", %{}),
      422,
      "validation_failed"
    )
  end

  test "email confirmations are rate limited", %{auth: auth} do
    for _ <- 1..10, do: post(auth, ~p"/api/v1/settings/email-confirmations", %{token: "invalid"})
    result = post(auth, ~p"/api/v1/settings/email-confirmations", %{token: "invalid"})
    error = assert_error(result, 429, "rate_limited")
    assert error["retryAfter"] > 0
    assert get_resp_header(result, "retry-after") != []
  end

  test "account deletion is rate limited", %{auth: auth, user: user} do
    scope = scope_fixture(user)
    membership_fixture(scope, user_fixture())

    for _ <- 1..5,
        do: assert_error(delete(auth, ~p"/api/v1/settings/account"), 409, "transfer_ownership")

    result = delete(auth, ~p"/api/v1/settings/account")
    assert_error(result, 429, "rate_limited")
    assert get_resp_header(result, "retry-after") != []
  end

  defp sudo_token(_conn, user, _session, :impersonation),
    do: Accounts.generate_api_token(user, %{}, impersonator_user_id: superadmin_fixture().id).token

  defp sudo_token(_conn, _user, session, state) do
    until = if state == :expired, do: DateTime.add(DateTime.utc_now(:second), -1)
    Repo.update!(Ecto.Changeset.change(Repo.get!(Session, current_id(session)), sudo_until: until))
    session["token"]
  end

  defp confirmation_token(_conn, _auth, _user, :unknown), do: "not-valid!"

  defp confirmation_token(conn, auth, user, outcome) do
    caller =
      if outcome == :another_user,
        do: bearer(conn, sign_in(conn, user_fixture(password: "correct horse battery"))["token"]),
        else: auth

    assert json_response(put(caller, ~p"/api/v1/settings/email", %{email: unique_email()}), 202)
    token = email_token("/settings/email-confirmations/")

    if outcome == :expired do
      Repo.update_all(from(t in UserToken, where: t.user_id == ^user.id),
        set: [inserted_at: DateTime.add(DateTime.utc_now(:second), -8, :day)]
      )
    end

    token
  end

  defp current_id(session),
    do: Repo.get_by!(Session, token_hash: :crypto.hash(:sha256, session["token"])).id

  defp event_count(action, actor_id),
    do:
      Repo.aggregate(
        from(a in Audit.AuditEvent, where: a.action == ^action and a.actor_id == ^actor_id),
        :count
      )

  defp published_legal_fixture(slug) do
    scope = Accounts.Scope.for_user(superadmin_fixture())
    document = StarterKit.Legal.get_document!(scope, slug)

    {:ok, version} =
      StarterKit.Legal.create_version(
        scope,
        document,
        %{titles: %{"en" => slug}, bodies: %{"en" => "Accepted terms"}},
        publish: true
      )

    version
  end

  defp settings_request(conn, method, path, params),
    do: Phoenix.ConnTest.dispatch(conn, @endpoint, method, path, params)
end
