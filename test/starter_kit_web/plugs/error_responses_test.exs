defmodule StarterKitWeb.Plugs.ErrorResponsesTest do
  use StarterKitWeb.ConnCase, async: true

  defp no_index_no_store?(headers) do
    {"x-robots-tag", "noindex"} in headers and {"cache-control", "private, no-store"} in headers
  end

  test "an unmatched route (the last-resort error page) is noindex and not cached", %{conn: conn} do
    conn = get(conn, "/no/such/page/here")

    assert conn.status == 404
    assert no_index_no_store?(conn.resp_headers)
    assert conn.resp_body =~ ~s(<meta name="robots" content="noindex")
  end

  test "an API legal error (a missing document) is noindex and not cached", %{conn: conn} do
    conn = get(conn, ~p"/api/v1/legal-pages/no-such-document")

    assert conn.status == 404
    assert no_index_no_store?(conn.resp_headers)
  end

  test "an unknown locale prefix (PathLocale's 404) is noindex and not cached", %{conn: conn} do
    conn = get(conn, "/xx")

    assert conn.status == 404
    assert no_index_no_store?(conn.resp_headers)
  end

  test "a normal page keeps its own headers", %{conn: conn} do
    conn = get(conn, ~p"/")

    assert conn.status == 200
    assert get_resp_header(conn, "x-robots-tag") == []
    refute get_resp_header(conn, "cache-control") == ["private, no-store"]
  end
end
