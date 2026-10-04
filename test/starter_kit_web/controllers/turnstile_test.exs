defmodule StarterKitWeb.TurnstileTest do
  use StarterKitWeb.ConnCase, async: true
  import Swoosh.TestAssertions
  alias StarterKit.{AbuseProtection, Accounts}

  setup %{conn: conn} do
    put_flag(:turnstile, true)
    %{conn: %{conn | remote_ip: {192, 0, 2, rem(System.unique_integer([:positive]), 250)}}}
  end

  defp answer(body), do: Req.Test.stub(AbuseProtection, &Req.Test.json(&1, body))
  defp accept(action), do: answer(%{success: true, hostname: "app.example.com", action: action})

  defp sign_up(conn, email, token) do
    post(conn, ~p"/api/v1/auth/registrations", %{
      name: "Ana",
      email: email,
      termsAccepted: true,
      turnstileToken: token
    })
  end

  test "a refused challenge creates no account or email", %{conn: conn} do
    email = unique_email()
    answer(%{success: false})

    for token <- [nil, "rejected"] do
      result = sign_up(conn, email, token)

      assert json_response(result, 422)["error"]["details"]["turnstileToken"] == [
               "validation.turnstile_required"
             ]

      refute Accounts.get_user_by_email(email)
    end

    assert_no_email_sent()
  end

  test "a passing challenge creates the account", %{conn: conn} do
    accept("registration")
    email = unique_email()
    assert json_response(sign_up(conn, email, "valid"), 201)
    assert Accounts.get_user_by_email(email)
    assert_email_sent()
  end

  test "a challenge for another action fails", %{conn: conn} do
    accept("magic_link")
    email = unique_email()
    assert json_response(sign_up(conn, email, "valid"), 422)
    refute Accounts.get_user_by_email(email)
  end

  test "magic requests need a challenge but spending an emailed token does not", %{conn: conn} do
    user = user_fixture()
    answer(%{success: false})
    assert json_response(post(conn, ~p"/api/v1/auth/magic-links", %{email: user.email}), 422)
    assert_no_email_sent()
    accept("magic_link")

    assert json_response(
             post(conn, ~p"/api/v1/auth/magic-links", %{email: user.email, turnstileToken: "valid"}),
             200
           )

    assert_email_sent()
    token = capture_token(&Accounts.deliver_login_instructions(user.email, &1))

    assert json_response(post(conn, ~p"/api/v1/auth/magic-links/#{token}/session", %{}), 201)[
             "data"
           ]["token"]
  end

  test "bootstrap sends only the public widget configuration", %{conn: conn} do
    result = get(conn, ~p"/api/v1/bootstrap")

    assert json_response(result, 200)["data"]["turnstile"] == %{
             "required" => true,
             "siteKey" => "public-site-key"
           }

    refute result.resp_body =~ "fixture-secret"
  end

  test "protection off needs no token", %{conn: conn} do
    put_flag(:turnstile, false)

    assert json_response(get(conn, ~p"/api/v1/bootstrap"), 200)["data"]["turnstile"] == %{
             "required" => false,
             "siteKey" => nil
           }

    assert json_response(sign_up(conn, unique_email(), nil), 201)
  end
end
