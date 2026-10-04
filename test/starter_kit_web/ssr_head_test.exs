defmodule StarterKitWeb.SSRHeadTest do
  @moduledoc """
  The raw HTML a crawler gets. The real SSR bundle is built once here and the public pages
  are rendered through it: one `<title>` per page, the page's own title (not the app name),
  escaped exactly once, and the React markup inside `#app` (so the client hydrates it).
  """
  # Turns SSR on globally: not async.
  use StarterKitWeb.ConnCase, async: false

  alias StarterKit.Accounts.Scope
  alias StarterKit.{I18n, Legal}

  setup_all do
    dir = Path.join(System.tmp_dir!(), "starter-kit-ssr-#{System.unique_integer([:positive])}")

    {output, status} =
      System.cmd(
        "pnpm",
        ["exec", "vite", "build", "--ssr", "js/ssr.tsx", "--outDir", dir, "--logLevel", "error"],
        stderr_to_stdout: true
      )

    assert status == 0, output
    on_exit(fn -> File.rm_rf!(dir) end)

    start_supervised!({Inertia.SSR, path: dir, pool_size: 1})

    previous = Application.get_env(:starter_kit, :ssr)
    Application.put_env(:starter_kit, :ssr, true)
    on_exit(fn -> Application.put_env(:starter_kit, :ssr, previous) end)
    :ok
  end

  defp titles(html), do: Regex.scan(~r/<title[^>]*>(.*?)<\/title>/s, html, capture: :all_but_first)

  defp title!(html) do
    assert [[title]] = titles(html)
    String.trim(title)
  end

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  test "home: the localized SEO title, server-rendered", %{conn: conn} do
    for {path, locale} <- [{"/", "en"}, {"/es", "es"}] do
      html = conn |> get(path) |> html_response(200)

      assert title!(html) == escape(I18n.t("home.seo.title", %{}, locale))
      assert html =~ ~r/<div[^>]*id="app"[^>]*>\s*<[a-z]/
    end
  end

  test "JSON-LD is in the head and a value cannot close its script tag", %{conn: conn} do
    previous = Application.get_env(:starter_kit, :app_name)
    Application.put_env(:starter_kit, :app_name, "Acme</script><script>alert(1)</script>")
    on_exit(fn -> Application.put_env(:starter_kit, :app_name, previous) end)

    html = conn |> get(~p"/") |> html_response(200)
    [head, _body] = String.split(html, "</head>", parts: 2)

    assert [_organization, _website] = Regex.scan(~r/<script[^>]*application\/ld\+json/, head)
    assert head =~ ~s(Acme\\u003c/script>)
    refute html =~ "<script>alert(1)"
  end

  test "a title with & and < is escaped once, never &amp;amp;", %{conn: conn} do
    scope = Scope.for_user(superadmin_fixture())
    [doc] = Legal.list_documents(scope) |> Enum.filter(&(&1.slug == "terms"))

    {:ok, _} =
      Legal.create_version(
        scope,
        doc,
        %{"titles" => %{"en" => "Terms & <rules>"}, "bodies" => %{"en" => "Hello"}},
        publish: true
      )

    html = conn |> get(~p"/legal/terms") |> html_response(200)

    assert title!(html) == "Terms &amp; &lt;rules&gt;"
    refute html =~ "&amp;amp;"
  end
end
