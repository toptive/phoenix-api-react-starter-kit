defmodule StarterKitWeb.Plugs.SecureCookiesTest do
  # Changes global config: not async.
  use StarterKitWeb.ConnCase, async: false

  setup do
    on_exit(fn -> Application.delete_env(:starter_kit, :secure_cookies) end)
  end

  defp set_cookies(conn), do: Plug.Conn.get_resp_header(conn, "set-cookie")

  test "with secure_cookies on, every cookie (session, XSRF-TOKEN) is Secure", %{conn: conn} do
    Application.put_env(:starter_kit, :secure_cookies, true)

    cookies =
      conn |> log_in_user(user_fixture()) |> get(~p"/settings/appearance/edit") |> set_cookies()

    assert Enum.any?(cookies, &String.starts_with?(&1, "XSRF-TOKEN="))
    assert Enum.any?(cookies, &String.starts_with?(&1, "_starter_kit_key="))
    assert Enum.all?(cookies, &(&1 =~ ~r/;\s*secure/i))
  end

  test "off by default (dev and test run on plain HTTP)", %{conn: conn} do
    cookies =
      conn |> log_in_user(user_fixture()) |> get(~p"/settings/appearance/edit") |> set_cookies()

    refute Enum.any?(cookies, &(&1 =~ ~r/;\s*secure/i))
  end
end
