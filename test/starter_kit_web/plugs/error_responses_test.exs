defmodule StarterKitWeb.Plugs.ErrorResponsesTest do
  use StarterKitWeb.ConnCase, async: true

  defp no_index_no_store?(headers) do
    {"x-robots-tag", "noindex"} in headers and {"cache-control", "private, no-store"} in headers
  end

  test "an API legal error (a missing document) is noindex and not cached", %{conn: conn} do
    conn = get(conn, ~p"/api/v1/legal-pages/no-such-document")

    assert conn.status == 404
    assert no_index_no_store?(conn.resp_headers)
  end
end
