defmodule StarterKitWeb.SiteIndexingTest do
  # Changes application env (allowed_training_bots): not async.
  use StarterKitWeb.ConnCase, async: false

  setup do
    root =
      Path.join(System.tmp_dir!(), "starter-kit-indexing-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    File.write!(Path.join(root, "index.html"), "<html><head></head><body>SPA</body></html>")
    Application.put_env(:starter_kit, :spa_static_dir, root)

    on_exit(fn ->
      Application.delete_env(:starter_kit, :spa_static_dir)
      File.rm_rf!(root)
    end)

    :ok
  end

  test "robots.txt has groups for search and AI-training crawlers", %{conn: conn} do
    robots = conn |> get(~p"/robots.txt") |> response(200)

    assert robots =~ "User-agent: *\nAllow: /\nDisallow: /admin\n"
    assert robots =~ "User-agent: OAI-SearchBot\nAllow: /\n"
    assert robots =~ "User-agent: GPTBot\nAllow: /\n"
    assert robots =~ "Sitemap: http://localhost:5173/sitemap.xml"

    Application.put_env(:starter_kit, :allowed_training_bots, ~w(ClaudeBot))
    on_exit(fn -> Application.delete_env(:starter_kit, :allowed_training_bots) end)

    robots = conn |> get(~p"/robots.txt") |> response(200)
    assert robots =~ "User-agent: GPTBot\nDisallow: /\n"
    assert robots =~ "User-agent: ClaudeBot\nAllow: /\n"
  end

  test "an open site sends no indexing header", %{conn: conn} do
    assert conn |> get(~p"/") |> get_resp_header("x-robots-tag") == []
  end

  test "the lock keeps every response out of search indexes", %{conn: conn} do
    put_flag(:site_indexing, false)

    page = get(conn, ~p"/")
    assert html_response(page, 200) =~ ~s(name="robots" content="noindex")
    assert get_resp_header(page, "x-robots-tag") == ["noindex, nofollow"]

    assert conn |> get("/favicon.svg") |> get_resp_header("x-robots-tag") == ["noindex, nofollow"]

    not_found = get(conn, "/xx/legal/terms")
    assert html_response(not_found, 200)
    assert get_resp_header(not_found, "x-robots-tag") == ["noindex, nofollow"]

    assert conn |> get(~p"/robots.txt") |> response(200) ==
             "User-agent: *\nDisallow: /\n\nSitemap: http://localhost:5173/sitemap.xml\n"

    sitemap = conn |> get(~p"/sitemap.xml") |> response(200)
    refute sitemap =~ "<url>"
  end
end
