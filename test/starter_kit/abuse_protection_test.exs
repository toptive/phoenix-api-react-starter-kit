defmodule StarterKit.AbuseProtectionTest do
  use ExUnit.Case, async: true

  import StarterKit.FlagHelpers

  alias StarterKit.AbuseProtection

  setup do: put_flag(:turnstile, true)

  defp answer(body), do: Req.Test.stub(AbuseProtection, &Req.Test.json(&1, body))

  test "sends the token, the secret and the client IP; accepts our hostname and action" do
    Req.Test.stub(AbuseProtection, fn conn ->
      assert conn.host == "challenges.cloudflare.com"
      assert conn.request_path == "/turnstile/v0/siteverify"
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      assert URI.decode_query(body) == %{
               "secret" => "fixture-secret",
               "response" => "token",
               "remoteip" => "192.0.2.1"
             }

      Req.Test.json(conn, %{success: true, hostname: "app.example.com", action: "registration"})
    end)

    assert :ok = AbuseProtection.verify("token", "registration", {192, 0, 2, 1})
  end

  test "refuses missing, malformed, oversized and used tokens" do
    answer(%{success: false, "error-codes": ["timeout-or-duplicate"]})

    for token <- [nil, "", %{}, String.duplicate("x", 2049), "used-token"] do
      assert {:error, :verification_required} =
               AbuseProtection.verify(token, "registration", {127, 0, 0, 1})
    end
  end

  test "fails closed on another hostname or action, a test-key answer and provider errors" do
    for body <- [
          %{success: true, hostname: "other.example", action: "registration"},
          %{success: true, hostname: "app.example.com", action: "magic_link"},
          %{success: true, hostname: "example.com", metadata: %{result_with_testing_key: true}},
          %{success: true},
          %{success: false}
        ] do
      answer(body)

      assert {:error, :verification_required} =
               AbuseProtection.verify("token", "registration", {127, 0, 0, 1})
    end

    for status <- [302, 429, 503] do
      Req.Test.stub(AbuseProtection, &Plug.Conn.send_resp(&1, status, "provider body"))

      assert {:error, :verification_required} =
               AbuseProtection.verify("token", "registration", {127, 0, 0, 1})
    end

    Req.Test.stub(AbuseProtection, &Req.Test.transport_error(&1, :timeout))

    assert {:error, :verification_required} =
             AbuseProtection.verify("token", "registration", {127, 0, 0, 1})
  end

  test "protection off: every request passes and the page gets no key" do
    put_flag(:turnstile, false)

    assert :ok = AbuseProtection.verify(nil, "magic_link", {127, 0, 0, 1})
    assert AbuseProtection.widget() == %{required: false, site_key: nil}
  end

  test "the page gets the public site key, never the secret" do
    assert AbuseProtection.widget() == %{required: true, site_key: "public-site-key"}
  end

  describe "boot check" do
    @ready [site_key: "0x4AAAAAAA-site", secret_key: "0x4AAAAAAA-secret", hostname: "app.com"]

    test "real keys and a hostname are ready" do
      assert AbuseProtection.config_problems(@ready) == []
    end

    test "names every missing piece and refuses Cloudflare test keys" do
      assert AbuseProtection.config_problems([]) == [
               "TURNSTILE_SITE_KEY is missing",
               "TURNSTILE_SECRET_KEY is missing",
               "TURNSTILE_HOSTNAME (or PHX_HOST) is missing"
             ]

      for {key, value} <- [
            site_key: "1x00000000000000000000AA",
            site_key: "3x00000000000000000000FF",
            secret_key: "1x0000000000000000000000000000000AA",
            secret_key: "2x0000000000000000000000000000000AA"
          ] do
        assert AbuseProtection.config_problems(Keyword.put(@ready, key, value)) ==
                 ["a Cloudflare test key cannot protect production"]
      end
    end

    test "Turnstile ON with a test key stops the boot; OFF never does" do
      dummy = Keyword.put(@ready, :site_key, "1x00000000000000000000AA")
      check = [turnstile: fn -> AbuseProtection.config_problems(dummy) end]

      assert_raise RuntimeError,
                   ~r/TURNSTILE_REQUIRED: a Cloudflare test key cannot protect production/,
                   fn -> StarterKit.Flags.check!(check) end

      put_flag(:turnstile, false)
      assert :ok = StarterKit.Flags.check!(check)
    end
  end
end

defmodule StarterKit.AbuseProtectionTestKeysTest do
  # Changes the global config: not async.
  use ExUnit.Case, async: false

  import StarterKit.FlagHelpers

  alias StarterKit.AbuseProtection

  setup do
    put_flag(:turnstile, true)
    original = Application.get_env(:starter_kit, AbuseProtection)
    on_exit(fn -> Application.put_env(:starter_kit, AbuseProtection, original) end)
    %{original: original}
  end

  test "a Cloudflare test-key answer counts only while the secret is a test secret (dev)",
       %{original: original} do
    Req.Test.stub(
      AbuseProtection,
      &Req.Test.json(&1, %{
        success: true,
        hostname: "example.com",
        metadata: %{result_with_testing_key: true}
      })
    )

    Application.put_env(
      :starter_kit,
      AbuseProtection,
      Keyword.put(original, :secret_key, "1x0000000000000000000000000000000AA")
    )

    assert :ok = AbuseProtection.verify("XXXX.DUMMY.TOKEN.XXXX", "registration", {127, 0, 0, 1})
  end
end
