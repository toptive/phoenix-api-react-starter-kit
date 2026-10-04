defmodule StarterKitWeb.SpaTest do
  use StarterKitWeb.ConnCase, async: false
  import StarterKitWeb.ApiHelpers

  setup do
    root = Path.join(System.tmp_dir!(), "starter-kit-spa-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, "es/legal/terms"))

    File.write!(
      Path.join(root, "index.html"),
      "<html><script data-bootstrap>boot()</script><div id=\"root\">app</div></html>"
    )

    File.write!(
      Path.join(root, "es/legal/terms/index.html"),
      "<html>published terms<script data-bootstrap>boot()</script></html>"
    )

    Application.put_env(:starter_kit, :spa_static_dir, root)

    on_exit(fn ->
      Application.delete_env(:starter_kit, :spa_static_dir)
      File.rm_rf!(root)
    end)

    :ok
  end

  test "deep links and browser 404s return the SPA with only its bootstrap nonce", %{conn: conn} do
    for path <- ["/", "/es", "/dashboard", "/settings/appearance/edit", "/no/such/page", "/xx"] do
      response = get(conn, path)
      body = html_response(response, 200)
      assert body =~ "app"
      assert body =~ ~s(nonce="#{response.assigns.csp_nonce}")

      assert get_resp_header(response, "content-security-policy") |> hd() =~
               "'nonce-#{response.assigns.csp_nonce}'"

      assert get_resp_header(response, "cache-control") == ["private, no-store"]
      assert response.resp_cookies == %{}
    end
  end

  test "published public pages use their own index, safely falling back otherwise", %{conn: conn} do
    assert html_response(get(conn, "/es/legal/terms"), 200) =~ "published terms"
    assert html_response(get(conn, "/es/legal/privacy"), 200) =~ "app"
    assert html_response(get(conn, "/%2e%2e/secret"), 200) =~ "app"
  end

  test "unknown backend routes keep API errors and jobs protection", %{conn: conn} do
    assert_error(get(api_conn(conn), "/api/v1/unknown"), 404, "not_found")
    assert_error(post(api_conn(conn), "/api/v1/unknown", %{}), 404, "not_found")
    assert get(conn, "/admin/jobs/unknown").status == 404
    assert get(conn, "/dev/unknown").status == 404
    assert get(conn, "/webhooks/unknown").status == 404
    assert response(get(conn, "/health"), 200) == "ok"
  end
end
