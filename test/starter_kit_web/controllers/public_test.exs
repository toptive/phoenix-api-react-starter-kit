defmodule StarterKitWeb.PublicTest do
  use StarterKitWeb.ConnCase, async: false
  alias StarterKit.{Accounts, Legal}

  defmodule UnavailableRepo do
    use Ecto.Repo, otp_app: :starter_kit, adapter: Ecto.Adapters.Postgres
  end

  setup %{conn: conn} do
    previous = Application.get_env(:starter_kit, :public_url)
    Application.put_env(:starter_kit, :public_url, "https://app.example.com")
    on_exit(fn -> Application.put_env(:starter_kit, :public_url, previous) end)
    %{conn: conn}
  end

  test "health answers text, no-store and never a canonical-host redirect", %{conn: conn} do
    previous = Application.get_env(:starter_kit, :canonical_host)
    Application.put_env(:starter_kit, :canonical_host, "api.example.com")
    on_exit(fn -> Application.put_env(:starter_kit, :canonical_host, previous) end)
    result = get(conn, ~p"/health")
    assert response(result, 200) == "ok"
    assert get_resp_header(result, "content-type") == ["text/plain; charset=utf-8"]
    assert get_resp_header(result, "cache-control") == ["no-store"]
    assert get_resp_header(result, "set-cookie") == []
  end

  @tag :capture_log
  test "health returns text 503 and no-store while its database is unavailable", %{conn: conn} do
    start_supervised!(
      {UnavailableRepo,
       hostname: "127.0.0.1",
       port: 1,
       username: "test",
       password: "test",
       database: "unavailable",
       pool_size: 1,
       queue_target: 10,
       queue_interval: 100}
    )

    previous = Application.get_env(:starter_kit, StarterKit.Health)
    Application.put_env(:starter_kit, StarterKit.Health, repo: UnavailableRepo)
    on_exit(fn -> Application.put_env(:starter_kit, StarterKit.Health, previous) end)
    result = get(conn, ~p"/health")
    assert response(result, 503) == "database unavailable"
    assert get_resp_header(result, "content-type") == ["text/plain; charset=utf-8"]
    assert get_resp_header(result, "cache-control") == ["no-store"]
  end

  test "sitemap lists home and only published legal pages in every locale with alternates", %{
    conn: conn
  } do
    scope = Accounts.Scope.for_user(superadmin_fixture())
    terms = Legal.get_document!(scope, "terms")

    {:ok, _} =
      Legal.create_version(scope, terms, %{titles: %{"en" => "Terms"}, bodies: %{"en" => "Text"}},
        publish: true
      )

    privacy = Legal.get_document!(scope, "privacy")

    {:ok, _} =
      Legal.create_version(scope, privacy, %{
        titles: %{"en" => "Privacy"},
        bodies: %{"en" => "Text"}
      })

    result = get(conn, ~p"/sitemap.xml")
    xml = response(result, 200)
    assert get_resp_header(result, "content-type") == ["application/xml; charset=utf-8"]
    assert get_resp_header(result, "set-cookie") == []
    assert length(Regex.scan(~r/<url>/, xml)) == 4

    for path <- ["/", "/es", "/legal/terms", "/es/legal/terms"],
        do: assert(xml =~ "<loc>https://app.example.com#{path}</loc>")

    refute xml =~ "/legal/privacy"
    refute xml =~ "/legal/cookies"

    for {locale, path} <- [
          {"en", "/"},
          {"es", "/es"},
          {"en", "/legal/terms"},
          {"es", "/es/legal/terms"}
        ] do
      assert length(
               Regex.scan(
                 ~r/#{Regex.escape("hreflang=\"#{locale}\" href=\"https://app.example.com#{path}\"")}/,
                 xml
               )
             ) == 2
    end
  end

  test "robots repeats every private SPA path in each public crawler group", %{conn: conn} do
    result = get(conn, ~p"/robots.txt")
    body = response(result, 200)
    assert get_resp_header(result, "content-type") == ["text/plain; charset=utf-8"]
    groups = String.split(body, "\n\n")

    for agent <-
          ~w(* Googlebot Bingbot OAI-SearchBot ChatGPT-User Claude-SearchBot Claude-User PerplexityBot Perplexity-User GPTBot ClaudeBot Google-Extended CCBot) do
      group = Enum.find(groups, &String.starts_with?(&1, "User-agent: #{agent}\n"))
      assert group =~ "Allow: /\n"

      for private <-
            ~w(/admin /api /dashboard /onboarding /settings /session /registration /magic-links /invitations /auth /email-subscriptions /sudo/new /session/check-your-email /errors/403 /errors/404 /errors/500),
          do: assert("Disallow: #{private}" in String.split(group, "\n"))
    end

    assert String.ends_with?(body, "Sitemap: https://app.example.com/sitemap.xml\n")
  end

  test "indexing lock gives an empty sitemap and robots disallow-all with the public sitemap", %{
    conn: conn
  } do
    put_flag(:site_indexing, false)
    result = get(conn, ~p"/sitemap.xml")
    refute response(result, 200) =~ "<url>"
    assert get_resp_header(result, "x-robots-tag") == ["noindex, nofollow"]
    result = get(conn, ~p"/robots.txt")

    assert response(result, 200) ==
             "User-agent: *\nDisallow: /\n\nSitemap: https://app.example.com/sitemap.xml\n"

    assert get_resp_header(result, "x-robots-tag") == ["noindex, nofollow"]
  end

  test "canonical host remains active for crawler infrastructure", %{conn: conn} do
    previous = Application.get_env(:starter_kit, :canonical_host)
    Application.put_env(:starter_kit, :canonical_host, "api.example.com")
    on_exit(fn -> Application.put_env(:starter_kit, :canonical_host, previous) end)
    assert redirected_to(get(conn, ~p"/sitemap.xml"), 301) =~ "/sitemap.xml"
  end
end
