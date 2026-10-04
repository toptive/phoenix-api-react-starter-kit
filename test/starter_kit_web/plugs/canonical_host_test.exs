defmodule StarterKitWeb.Plugs.CanonicalHostTest do
  # Changes application env (canonical_host): not async.
  use StarterKitWeb.ConnCase, async: false

  setup do
    Application.put_env(:starter_kit, :canonical_host, "localhost")
    on_exit(fn -> Application.delete_env(:starter_kit, :canonical_host) end)
  end

  defp on_host(conn, host), do: %{conn | host: host}

  test "another host gets a permanent redirect with the same path and query", %{conn: conn} do
    page = conn |> on_host("www.localhost") |> get("/legal/terms?ref=ad&x=1")
    assert page.status == 301
    assert get_resp_header(page, "location") == ["http://localhost:4002/legal/terms?ref=ad&x=1"]

    assert conn |> on_host("10.0.0.5") |> get("/") |> redirected_to(301) == "http://localhost:4002/"
  end

  test "a form post keeps its method (308)", %{conn: conn} do
    assert conn |> on_host("www.localhost") |> post("/session") |> redirected_to(308) ==
             "http://localhost:4002/session"
  end

  test "the canonical host and the health check pass through", %{conn: conn} do
    assert conn |> on_host("localhost") |> get(~p"/") |> html_response(200)
    assert conn |> on_host("10.0.0.5") |> get(~p"/health") |> response(200) == "ok"
  end

  test "off without a configured host", %{conn: conn} do
    Application.delete_env(:starter_kit, :canonical_host)
    assert conn |> on_host("www.localhost") |> get(~p"/") |> html_response(200)
  end
end
