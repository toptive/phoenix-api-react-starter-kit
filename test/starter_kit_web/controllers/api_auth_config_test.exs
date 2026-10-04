defmodule StarterKitWeb.ApiAuthConfigTest do
  use StarterKitWeb.ConnCase, async: false

  import StarterKitWeb.ApiHelpers
  alias StarterKit.Accounts

  setup %{conn: conn} do
    keys = [
      :signup_mode,
      :google_auth,
      :google_req_options,
      :cors_origins,
      :tenancy,
      :native_scheme
    ]

    old = Map.new(keys, &{&1, Application.get_env(:starter_kit, &1)})

    on_exit(fn ->
      for {key, value} <- old do
        if is_nil(value),
          do: Application.delete_env(:starter_kit, key),
          else: Application.put_env(:starter_kit, key, value)
      end
    end)

    %{
      conn: %{
        put_req_header(conn, "content-type", "application/json")
        | remote_ip: {198, 51, 100, rem(System.unique_integer([:positive]), 250)}
      }
    }
  end

  test "closed and invitation-only sign-up refuse, existing users still sign in", %{conn: conn} do
    user = user_fixture(password: "correct horse battery")

    for {mode, code} <- [closed: "signup_closed", invite: "invitation_required"] do
      Application.put_env(:starter_kit, :signup_mode, mode)
      email = unique_email()

      result =
        post(conn, ~p"/api/v1/auth/registrations", %{name: "Ana", email: email, termsAccepted: true})

      assert json_response(result, 422)["error"]["code"] == code
      refute Accounts.get_user_by_email(email)

      assert json_response(
               post(conn, ~p"/api/v1/auth/sessions", %{
                 email: user.email,
                 password: "correct horse battery"
               }),
               201
             )["data"]["token"]
    end
  end

  test "invite mode accepts an invited address", %{conn: conn} do
    Application.put_env(:starter_kit, :signup_mode, :invite)
    email = unique_email()
    owner = scope_fixture()

    assert {:ok, _} =
             StarterKit.Organizations.create_invitation(
               owner,
               %{email: email, role: "member", access: "full"},
               fn token -> "http://localhost:5173/invitations/" <> token end
             )

    result =
      post(conn, ~p"/api/v1/auth/registrations", %{name: "Ana", email: email, termsAccepted: true})

    assert json_response(result, 202)
    assert Accounts.get_user_by_email(email)
  end

  test "CORS allows configured SPA origins, including preflights, without credential cookies", %{
    conn: conn
  } do
    Application.put_env(:starter_kit, :cors_origins, ["http://localhost:5173"])
    result = conn |> put_req_header("origin", "http://localhost:5173") |> get(~p"/api/v1/bootstrap")
    assert get_resp_header(result, "access-control-allow-origin") == ["http://localhost:5173"]
    assert get_resp_header(result, "access-control-allow-credentials") == []
    assert get_resp_header(result, "vary") == ["Origin"]

    preflight =
      conn
      |> put_req_header("origin", "http://localhost:5173")
      |> put_req_header("access-control-request-method", "POST")
      |> options(~p"/api/v1/auth/sessions")

    assert response(preflight, 204) == ""

    assert get_resp_header(preflight, "access-control-allow-headers") == [
             "Authorization, Content-Type, Accept-Language, If-None-Match"
           ]

    assert get_resp_header(preflight, "access-control-allow-methods") == [
             "GET, POST, PUT, DELETE, OPTIONS"
           ]

    assert get_resp_header(result, "access-control-expose-headers") == ["ETag, Retry-After"]
    denied = conn |> put_req_header("origin", "https://evil.example") |> get(~p"/api/v1/bootstrap")
    assert get_resp_header(denied, "access-control-allow-origin") == []
  end

  test "Google off returns 404 on both routes", %{conn: conn} do
    Application.put_env(:starter_kit, :google_auth, false)

    assert json_response(get(conn, ~p"/api/v1/auth/google/start"), 404)["error"]["code"] ==
             "not_found"

    result = get(conn, ~p"/api/v1/auth/google/callback?code=bad&state=bad")
    assert_error(result, 404, "not_found")
  end

  test "Google start signs cookie-free state; callback exchanges code and returns exact fragment",
       %{
         conn: conn
       } do
    Application.put_env(:starter_kit, :google_auth, true)
    Application.put_env(:starter_kit, :google_req_options, plug: {Req.Test, __MODULE__})

    Req.Test.stub(__MODULE__, fn conn ->
      case conn.request_path do
        "/token" ->
          Req.Test.json(conn, %{access_token: "google-fixture-token"})

        "/v1/userinfo" ->
          Req.Test.json(conn, %{
            sub: "google-fixture-id",
            email: "google@example.com",
            email_verified: true,
            name: "Ana"
          })
      end
    end)

    start = get(conn, ~p"/api/v1/auth/google/start?locale=es")
    url = redirected_to(start) |> URI.parse()
    assert url.host == "accounts.google.com"
    state = URI.decode_query(url.query)["state"]

    assert {:ok, %{locale: "es"}} =
             Phoenix.Token.verify(StarterKitWeb.Endpoint, "google-api-state", state, max_age: 600)

    assert get_resp_header(start, "set-cookie") == []
    assert URI.decode_query(url.query)["prompt"] == "select_account"
    callback = start |> recycle() |> get(~p"/api/v1/auth/google/callback?code=valid&state=#{state}")
    location = redirected_to(callback)
    assert location =~ "http://localhost:5173/auth/callback#token="
    assert URI.parse(location).query == nil
    token = URI.parse(location).fragment |> URI.decode_query() |> Map.fetch!("token")
    {user, _} = Accounts.get_user_by_api_token(token)
    assert user.email == "google@example.com"
    assert user.locale == "es"
    assert get_resp_header(callback, "cache-control") == ["private, no-store"]
    missing_cookie = get(conn, ~p"/api/v1/auth/google/callback?code=valid&state=#{state}")
    assert redirected_to(missing_cookie) =~ "#token="

    tampered =
      start
      |> recycle()
      |> get(~p"/api/v1/auth/google/callback?#{[code: "valid", state: state <> "bad"]}")

    assert redirected_to(tampered) =~ "#error=state_invalid"
  end

  test "Google refuses an unverified email", %{conn: conn} do
    Application.put_env(:starter_kit, :google_auth, true)
    Application.put_env(:starter_kit, :google_req_options, plug: {Req.Test, __MODULE__})

    Req.Test.stub(__MODULE__, fn conn ->
      case conn.request_path do
        "/token" ->
          Req.Test.json(conn, %{access_token: "fixture"})

        "/v1/userinfo" ->
          Req.Test.json(conn, %{
            sub: "unverified",
            email: "unverified@example.com",
            email_verified: false
          })
      end
    end)

    start = get(conn, ~p"/api/v1/auth/google/start")
    state = URI.parse(redirected_to(start)).query |> URI.decode_query() |> Map.fetch!("state")
    result = start |> recycle() |> get(~p"/api/v1/auth/google/callback?code=valid&state=#{state}")
    assert redirected_to(result) =~ "#error=email_not_verified"
    refute Accounts.get_user_by_email("unverified@example.com")
  end

  test "Google applies signup restrictions after verifying the provider identity", %{conn: conn} do
    Application.put_env(:starter_kit, :google_auth, true)
    Application.put_env(:starter_kit, :google_req_options, plug: {Req.Test, __MODULE__})

    Req.Test.stub(__MODULE__, fn conn ->
      case conn.request_path do
        "/token" ->
          Req.Test.json(conn, %{access_token: "fixture"})

        "/v1/userinfo" ->
          Req.Test.json(conn, %{
            sub: "restricted",
            email: "restricted@example.com",
            email_verified: true
          })
      end
    end)

    for {mode, reason} <- [closed: "signup_closed", invite: "invitation_required"] do
      Application.put_env(:starter_kit, :signup_mode, mode)
      start = get(conn, ~p"/api/v1/auth/google/start")
      state = URI.parse(redirected_to(start)).query |> URI.decode_query() |> Map.fetch!("state")
      result = start |> recycle() |> get(~p"/api/v1/auth/google/callback?code=valid&state=#{state}")
      assert redirected_to(result) == "http://localhost:5173/auth/callback#error=" <> reason
      refute Accounts.get_user_by_email("restricted@example.com")
    end
  end

  test "Google rejects unsafe return paths and invalid clients before redirecting", %{conn: conn} do
    Application.put_env(:starter_kit, :google_auth, true)

    for params <- [
          %{returnTo: "https://evil.example"},
          %{returnTo: "//evil.example"},
          %{returnTo: "/" <> String.duplicate("a", 201)},
          %{client: "other"}
        ] do
      assert_error(get(conn, ~p"/api/v1/auth/google/start?#{params}"), 400, "bad_request")
    end
  end

  test "native Google handoff includes expiresAt, new and the signed returnTo", %{conn: conn} do
    Application.put_env(:starter_kit, :google_auth, true)
    Application.put_env(:starter_kit, :native_scheme, "testapp")
    Application.put_env(:starter_kit, :google_req_options, plug: {Req.Test, __MODULE__})

    Req.Test.stub(__MODULE__, fn conn ->
      case conn.request_path do
        "/token" ->
          Req.Test.json(conn, %{access_token: "fixture"})

        "/v1/userinfo" ->
          Req.Test.json(conn, %{
            sub: "native-id",
            email: "native@example.com",
            email_verified: true,
            name: "Ana"
          })
      end
    end)

    start = get(conn, ~p"/api/v1/auth/google/start?client=native&returnTo=/settings/members")
    state = URI.parse(redirected_to(start)).query |> URI.decode_query() |> Map.fetch!("state")
    callback = get(conn, ~p"/api/v1/auth/google/callback?#{[code: "valid", state: state]}")
    url = URI.parse(redirected_to(callback))
    assert url.scheme == "testapp"
    assert url.host == "auth"
    assert url.path == "/callback"
    assert url.query == nil
    fragment = URI.decode_query(url.fragment)
    assert fragment["returnTo"] == "/settings/members"
    assert fragment["new"] == "1"
    assert {:ok, _, _} = DateTime.from_iso8601(fragment["expiresAt"])
    assert fragment["token"]
    assert get_resp_header(callback, "set-cookie") == []
    failure = get(conn, ~p"/api/v1/auth/google/callback?#{[error: "access_denied", state: state]}")
    assert redirected_to(failure) == "testapp://auth/callback#error=oauth_failed"
  end

  test "Google rejects expired signed state and limits callbacks to twenty per minute", %{
    conn: conn
  } do
    Application.put_env(:starter_kit, :google_auth, true)

    state =
      Phoenix.Token.sign(StarterKitWeb.Endpoint, "google-api-state", %{
        nonce: "n",
        client: "web",
        returnTo: "/dashboard",
        locale: "en",
        iat: System.system_time(:second) - 601
      })

    expired = get(conn, ~p"/api/v1/auth/google/callback?#{[code: "valid", state: state]}")
    assert redirected_to(expired) =~ "#error=state_invalid"
    for _ <- 1..19, do: get(conn, ~p"/api/v1/auth/google/callback?state=bad")
    assert_error(get(conn, ~p"/api/v1/auth/google/callback?state=bad"), 429, "rate_limited")
  end

  test "single tenancy shares the default org, first user owns it, and creation is forbidden", %{
    conn: conn
  } do
    Application.put_env(:starter_kit, :tenancy, :single)
    first = user_fixture(password: "correct horse battery")
    second = user_fixture(password: "correct horse battery")
    one = sign_in(conn, first)
    two = sign_in(conn, second)
    auth_one = current_auth(bearer(conn, one["token"]))
    auth_two = current_auth(bearer(conn, two["token"]))
    assert auth_one["organization"]["slug"] == "default"
    assert auth_one["membership"]["role"] == "owner"
    assert auth_two["organization"]["id"] == auth_one["organization"]["id"]
    assert auth_two["membership"]["role"] == "member"

    assert_error(
      post(bearer(conn, one["token"]), ~p"/api/v1/organizations", %{name: "Other"}),
      403,
      "forbidden"
    )
  end

  test "default CORS configuration permits the native origins without credential cookies", %{
    conn: conn
  } do
    for origin <- ["capacitor://localhost", "ionic://localhost", "http://localhost"] do
      result = conn |> put_req_header("origin", origin) |> get(~p"/api/v1/bootstrap")
      assert get_resp_header(result, "access-control-allow-origin") == [origin]
      assert get_resp_header(result, "access-control-allow-credentials") == []
      assert get_resp_header(result, "set-cookie") == []
    end
  end
end
