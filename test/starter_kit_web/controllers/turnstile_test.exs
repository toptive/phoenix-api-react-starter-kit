defmodule StarterKitWeb.TurnstileTest do
  use StarterKitWeb.ConnCase, async: true

  import Swoosh.TestAssertions

  alias StarterKit.{AbuseProtection, Accounts}

  setup %{conn: conn} do
    put_flag(:turnstile, true)
    # Own IP per test: the auth rate limits count per client.
    %{conn: %{conn | remote_ip: {192, 0, 2, rem(System.unique_integer([:positive]), 250)}}}
  end

  defp answer(body), do: Req.Test.stub(AbuseProtection, &Req.Test.json(&1, body))
  defp accept(action), do: answer(%{success: true, hostname: "app.example.com", action: action})

  defp sign_up(conn, email, token) do
    user = %{"name" => "Ana", "email" => email, "termsAccepted" => true, "turnstileToken" => token}
    post(conn, ~p"/registration", %{"user" => user})
  end

  test "sign-up without a passing check creates no account and sends no email", %{conn: conn} do
    email = unique_email()
    answer(%{success: false})

    for token <- [nil, "rejected"] do
      result = sign_up(conn, email, token)

      assert redirected_to(result) == ~p"/registration/new"

      assert get_session(result, "inertia_errors")["turnstile_token"] =~
               "confirm that you're a person"

      refute Accounts.get_user_by_email(email)
    end

    assert_no_email_sent()
  end

  test "sign-up with a passing check creates the account", %{conn: conn} do
    accept("registration")
    email = unique_email()

    assert redirected_to(sign_up(conn, email, "valid")) == ~p"/session/new"
    assert Accounts.get_user_by_email(email)
    assert_email_sent()
  end

  test "a token for another action does not pass", %{conn: conn} do
    accept("magic_link")
    email = unique_email()

    assert redirected_to(sign_up(conn, email, "valid")) == ~p"/registration/new"
    refute Accounts.get_user_by_email(email)
  end

  test "\"email me a link\" needs the check; the emailed link stays one click", %{conn: conn} do
    user = user_fixture()
    answer(%{success: false})

    result = post(conn, ~p"/magic-links", %{"user" => %{"email" => user.email}})
    assert redirected_to(result) == ~p"/session/new"
    assert get_session(result, "inertia_errors")["turnstile_token"]
    assert_no_email_sent()

    accept("magic_link")
    params = %{"user" => %{"email" => user.email, "turnstileToken" => "valid"}}
    assert redirected_to(post(conn, ~p"/magic-links", params)) == ~p"/session/new"
    assert_email_sent()

    token = capture_token(&Accounts.deliver_login_instructions(user.email, &1))
    result = post(conn, ~p"/session", %{"user" => %{"token" => token}})
    assert get_session(result, :user_token)
  end

  test "the page gets only the public key, and the CSP allows the widget", %{conn: conn} do
    result = get(conn, ~p"/registration/new")

    assert inertia_props(result).turnstile == %{required: true, siteKey: "public-site-key"}
    refute html_response(result, 200) =~ "fixture-secret"
    [csp] = get_resp_header(result, "content-security-policy")
    assert csp =~ ~r/script-src [^;]*https:\/\/challenges\.cloudflare\.com/
    assert csp =~ "frame-src 'self' https://challenges.cloudflare.com"
  end

  test "protection off: no key, no Cloudflare in the CSP, forms work without a token", %{
    conn: conn
  } do
    put_flag(:turnstile, false)
    result = get(conn, ~p"/session/new")

    assert inertia_props(result).turnstile == %{required: false, siteKey: nil}
    [csp] = get_resp_header(result, "content-security-policy")
    refute csp =~ "challenges.cloudflare.com"

    email = unique_email()
    assert redirected_to(sign_up(conn, email, nil)) == ~p"/session/new"
    assert Accounts.get_user_by_email(email)
  end
end
