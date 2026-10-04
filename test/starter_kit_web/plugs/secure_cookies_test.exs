defmodule StarterKitWeb.Plugs.SecureCookiesTest do
  use StarterKitWeb.ConnCase, async: false
  import StarterKitWeb.ApiHelpers

  setup do
    previous = Application.get_env(:starter_kit, :secure_cookies)

    on_exit(fn ->
      if is_nil(previous),
        do: Application.delete_env(:starter_kit, :secure_cookies),
        else: Application.put_env(:starter_kit, :secure_cookies, previous)
    end)
  end

  for secure <- [true, false] do
    @secure secure
    test "jobs handoff cookies respect secure_cookies=#{secure}", %{conn: conn} do
      Application.put_env(:starter_kit, :secure_cookies, @secure)
      issued = StarterKit.Accounts.generate_api_token(superadmin_fixture())
      grant = post(bearer(api_conn(conn), issued.token), ~p"/api/v1/admin/jobs-access", %{})
      assert get_resp_header(grant, "set-cookie") == []
      url = json_response(grant, 201)["data"]["url"]
      cookies = get(conn, url) |> get_resp_header("set-cookie")
      assert Enum.any?(cookies, &String.starts_with?(&1, "_starter_kit_jobs="))
      assert Enum.all?(cookies, &(&1 =~ ~r/;\s*secure/i)) == @secure
    end
  end
end
