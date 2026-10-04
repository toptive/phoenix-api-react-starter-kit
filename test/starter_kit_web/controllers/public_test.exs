defmodule StarterKitWeb.PublicTest do
  use StarterKitWeb.ConnCase, async: true

  alias StarterKit.Accounts.Scope
  alias StarterKit.Legal

  test "the landing page is indexable and carries SEO props", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert inertia_component(conn) == "home/show"
    seo = inertia_props(conn).seo
    assert seo.canonical == "http://localhost:4002/"
    assert Enum.map(seo.alternates, & &1.hreflang) == ["en", "es", "x-default"]
    refute html_response(conn, 200) =~ ~s(name="robots" content="noindex")
  end

  test "every page carries the public flags", %{conn: conn} do
    assert inertia_props(get(conn, ~p"/")).flags == %{billing: true}

    put_flag(:billing, false)
    assert inertia_props(get(conn, ~p"/")).flags == %{billing: false}
  end

  test "localized public routes set the locale from the path", %{conn: conn} do
    conn = get(conn, ~p"/es")
    assert inertia_props(conn).locale == "es"
    assert inertia_props(conn).seo.canonical == "http://localhost:4002/es"
  end

  test "the default locale has one canonical URL and unknown locales do not exist", %{conn: conn} do
    assert conn |> get("/en/legal/terms") |> redirected_to(301) == "/legal/terms"
    assert conn |> get("/en") |> redirected_to(301) == "/"
    assert conn |> get("/xx") |> html_response(404)
    assert conn |> get("/xx/legal/terms") |> html_response(404)
  end

  test "legal pages show the published version, 404 otherwise", %{conn: conn} do
    assert conn |> get(~p"/legal/terms") |> inertia_component() == "errors/show"

    scope = Scope.for_user(superadmin_fixture())
    [doc] = Legal.list_documents(scope) |> Enum.filter(&(&1.slug == "terms"))

    {:ok, _} =
      Legal.create_version(
        scope,
        doc,
        %{"titles" => %{"en" => "Terms"}, "bodies" => %{"en" => "Hello"}},
        publish: true
      )

    conn = get(conn, ~p"/es/legal/terms")
    assert inertia_props(conn).page["title"] == "Terms"
    assert inertia_props(conn).page["body"] == "Hello"

    assert [%{"@type" => "BreadcrumbList", "itemListElement" => [home, page]}] =
             inertia_props(conn).seo.jsonLd

    assert {home["position"], home["item"]} == {1, "http://localhost:4002/es"}

    assert {page["position"], page["name"], page["item"]} ==
             {2, "Terms", "http://localhost:4002/es/legal/terms"}
  end

  test "sitemap, robots and health", %{conn: conn} do
    sitemap = conn |> get(~p"/sitemap.xml") |> response(200)
    assert sitemap =~ "<loc>http://localhost:4002/es</loc>"
    assert sitemap =~ ~s(hreflang="es")

    robots = conn |> get(~p"/robots.txt") |> response(200)
    assert robots =~ "Disallow: /admin"
    assert robots =~ "Sitemap: http://localhost:4002/sitemap.xml"

    assert conn |> get(~p"/health") |> response(200) == "ok"
  end

  test "the whole catalogue goes on a full load, not on Inertia visits that have it", %{conn: conn} do
    first = get(conn, ~p"/")
    assert %{"nav.sign_in" => "Sign in"} = inertia_props(first).translations
    version = inertia_props(first).i18nVersion

    again = conn |> inertia() |> put_req_header("x-i18n", "en:#{version}") |> get(~p"/")
    refute Map.has_key?(json_response(again, 200)["props"], "translations")
  end

  test "security headers", %{conn: conn} do
    conn = get(conn, ~p"/")
    [csp] = get_resp_header(conn, "content-security-policy")
    assert csp =~ "frame-ancestors 'none'"
    assert csp =~ "script-src 'self' 'nonce-"
  end

  describe "anonymous public pages are cookie-free and cacheable" do
    test "no cookie, no CSRF token, a public Cache-Control and an ETag", %{conn: conn} do
      first = get(conn, ~p"/")
      html = html_response(first, 200)

      assert get_resp_header(first, "set-cookie") == []
      assert first.resp_cookies == %{}
      refute html =~ "csrf-token"
      assert get_resp_header(first, "cache-control") == ["public, max-age=0, must-revalidate"]
      assert get_resp_header(first, "vary") == ["X-Inertia, Cookie"]
      assert [~s(W/") <> _ = etag] = get_resp_header(first, "etag")

      not_modified = conn |> put_req_header("if-none-match", etag) |> get(~p"/")
      assert response(not_modified, 304) == ""
      assert get_resp_header(not_modified, "set-cookie") == []

      # Another URL is another page (and another language).
      spanish = conn |> put_req_header("if-none-match", etag) |> get(~p"/es")
      assert html_response(spanish, 200)
      assert get_resp_header(spanish, "etag") != [etag]
    end

    test "the URL alone decides the language", %{conn: conn} do
      conn = conn |> put_req_header("accept-language", "es") |> get(~p"/")
      assert inertia_props(conn).locale == "en"
      assert html_response(conn, 200) =~ ~s(<html lang="en")
    end

    test "an Inertia visit is not cached and still sets no cookie", %{conn: conn} do
      conn = conn |> inertia() |> get(~p"/")
      assert get_resp_header(conn, "cache-control") == ["private, no-store"]
      assert get_resp_header(conn, "etag") == []
      assert get_resp_header(conn, "set-cookie") == []
      assert inertia_props(conn).auth == nil
    end

    test "a signed-in visitor gets a personal, uncached page", %{conn: conn} do
      user = user_fixture()
      conn = conn |> log_in_user(user) |> get(~p"/")
      assert html_response(conn, 200) =~ "csrf-token"
      assert inertia_props(conn).auth.user["email"] == user.email
      assert get_resp_header(conn, "cache-control") == ["private, no-store"]
      assert get_resp_header(conn, "etag") == []
    end

    test "form pages keep the session and the CSRF token", %{conn: conn} do
      conn = get(conn, ~p"/session/new")
      assert html_response(conn, 200) =~ "csrf-token"
      assert Map.has_key?(conn.resp_cookies, "XSRF-TOKEN")
      assert Map.has_key?(conn.resp_cookies, "_starter_kit_key")
    end
  end
end
