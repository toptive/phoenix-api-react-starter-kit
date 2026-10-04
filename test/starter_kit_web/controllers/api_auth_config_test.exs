defmodule StarterKitWeb.ApiAuthConfigTest do
  use StarterKitWeb.ConnCase, async: false

  alias StarterKit.Accounts

  setup %{conn: conn} do
    keys = [:signup_mode, :google_auth, :google_req_options, :cors_origins]
    old = Map.new(keys, &{&1, Application.get_env(:starter_kit, &1)})

    on_exit(fn ->
      for {key, value} <- old do
        if is_nil(value),
          do: Application.delete_env(:starter_kit, key),
          else: Application.put_env(:starter_kit, key, value)
      end
    end)

    %{conn: %{conn | remote_ip: {198, 51, 100, rem(System.unique_integer([:positive]), 250)}}}
  end

  test "closed and invitation-only sign-up refuse, existing users still sign in", %{conn: conn} do
    user = user_fixture(password: "correct horse battery")

    for {mode, code} <- [closed: "signup_closed", invite: "invitation_required"] do
      Application.put_env(:starter_kit, :signup_mode, mode)
      email = unique_email()

      result =
        post(conn, ~p"/api/v1/auth/registrations", %{name: "Ana", email: email, termsAccepted: true})

      assert json_response(result, 403)["error"]["code"] == code
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

    assert json_response(result, 201)
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
    assert get_resp_header(preflight, "access-control-allow-headers") |> hd() =~ "Authorization"
    denied = conn |> put_req_header("origin", "https://evil.example") |> get(~p"/api/v1/bootstrap")
    assert get_resp_header(denied, "access-control-allow-origin") == []
  end

  test "Google off returns 404 and failures redirect to the SPA", %{conn: conn} do
    Application.put_env(:starter_kit, :google_auth, false)

    assert json_response(get(conn, ~p"/api/v1/auth/google/start"), 404)["error"]["code"] ==
             "not_found"

    result = get(conn, ~p"/api/v1/auth/google/callback?code=bad&state=bad")
    assert redirected_to(result) == "http://localhost:5173/auth/callback#error=oauth_failed"
  end

  test "Google start signs state; callback verifies browser binding and exchanges code", %{
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

    assert start.resp_cookies["_api_oauth_state"].http_only
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
    assert redirected_to(missing_cookie) =~ "#error=oauth_failed"

    tampered =
      start
      |> recycle()
      |> get(~p"/api/v1/auth/google/callback?#{[code: "valid", state: state <> "bad"]}")

    assert redirected_to(tampered) =~ "#error=oauth_failed"
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
    assert redirected_to(result) =~ "#error=oauth_failed"
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
end
