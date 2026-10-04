defmodule StarterKitWeb.ApiTurnstileTest do
  use StarterKitWeb.ConnCase, async: true
  import StarterKitWeb.ApiHelpers
  alias StarterKit.{AbuseProtection, Repo}
  alias StarterKit.Accounts.User

  setup %{conn: conn}, do: %{conn: api_conn(conn)}

  for {path, action} <- [
        {"/api/v1/auth/registrations", "registration"},
        {"/api/v1/auth/magic-links", "magic_link"}
      ] do
    @path path
    @action action
    test "#{path} refuses missing tokens before creating work", %{conn: conn} do
      put_flag(:turnstile, true)
      before = Repo.aggregate(User, :count)
      Req.Test.stub(AbuseProtection, fn _ -> flunk("A missing token must not reach Cloudflare") end)
      result = post(conn, @path, params())
      details = assert_error(result, 422, "turnstile_failed")

      assert [%{"key" => "validation.turnstile_required", "message" => message}] =
               details["turnstileToken"]

      assert message != "validation.turnstile_required"
      assert Repo.aggregate(User, :count) == before
      refute_received {:email, _}
    end

    test "#{path} refuses wrong hostname/action, used tokens and provider timeout before writes", %{
      conn: conn
    } do
      put_flag(:turnstile, true)
      before = Repo.aggregate(User, :count)

      for answer <- [
            %{success: false},
            %{success: true, hostname: "evil.example", action: @action},
            %{success: true, hostname: "app.example.com", action: "wrong"},
            :timeout
          ] do
        Req.Test.stub(AbuseProtection, fn conn ->
          if answer == :timeout,
            do: Req.Test.transport_error(conn, :timeout),
            else: Req.Test.json(conn, answer)
        end)

        assert_error(
          post(conn, @path, Map.put(params(), :turnstileToken, "used-token")),
          422,
          "turnstile_failed"
        )

        assert Repo.aggregate(User, :count) == before
        refute_received {:email, _}
      end
    end

    test "#{path} verifies the action and hostname over HTTP then creates work", %{conn: conn} do
      put_flag(:turnstile, true)
      user = user_fixture()
      attrs = if @action == "magic_link", do: %{email: user.email}, else: params()

      Req.Test.stub(AbuseProtection, fn conn ->
        assert conn.request_path == "/turnstile/v0/siteverify"
        {:ok, body, conn} = read_body(conn)
        assert URI.decode_query(body)["response"] == "valid-token"
        Req.Test.json(conn, %{success: true, hostname: "app.example.com", action: @action})
      end)

      assert json_response(post(conn, @path, Map.put(attrs, :turnstileToken, "valid-token")), 202)[
               "data"
             ]["email"] == attrs.email

      assert_received {:email, _}
      bootstrap = json_response(get(conn, ~p"/api/v1/bootstrap"), 200)["data"]
      assert bootstrap["turnstile"] == %{"required" => true, "siteKey" => "public-site-key"}
      refute inspect(bootstrap) =~ "fixture-secret"
    end

    test "#{path} ignores the token while protection is off", %{conn: conn} do
      put_flag(:turnstile, false)

      Req.Test.stub(AbuseProtection, fn _ ->
        flunk("Disabled protection must not call Cloudflare")
      end)

      assert json_response(post(conn, @path, Map.put(params(), :turnstileToken, "ignored")), 202)
    end
  end

  defp params,
    do: %{
      name: "New Person",
      email: "new-#{System.unique_integer([:positive])}@example.com",
      termsAccepted: true
    }
end
