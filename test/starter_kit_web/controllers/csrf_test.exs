defmodule StarterKitWeb.CsrfTest do
  @moduledoc """
  Phoenix.ConnTest skips CSRF checks by default. This test turns them back on and sends
  the token the way the Inertia client does (X-XSRF-TOKEN from the XSRF-TOKEN cookie).
  """
  use StarterKitWeb.ConnCase, async: true

  defp with_csrf_checks(conn),
    do: update_in(conn.private, &Map.delete(&1, :plug_skip_csrf_protection))

  test "an Inertia form post with X-XSRF-TOKEN passes CSRF", %{conn: conn} do
    page =
      conn |> with_csrf_checks() |> log_in_user(user_fixture()) |> get(~p"/settings/profile/edit")

    token = page.resp_cookies["XSRF-TOKEN"].value

    conn =
      page
      |> recycle()
      |> with_csrf_checks()
      |> inertia()
      |> put_req_header("x-xsrf-token", token)
      |> put(~p"/settings/profile", %{"user" => %{"name" => "Ana"}})

    assert conn.status in [302, 303]
  end

  test "a post without a token is rejected", %{conn: conn} do
    page =
      conn |> with_csrf_checks() |> log_in_user(user_fixture()) |> get(~p"/settings/profile/edit")

    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      page |> recycle() |> with_csrf_checks() |> put(~p"/settings/profile", %{"user" => %{}})
    end
  end
end
