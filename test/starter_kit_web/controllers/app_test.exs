defmodule StarterKitWeb.AppTest do
  use StarterKitWeb.ConnCase, async: true

  setup :register_and_log_in_user

  test "dashboard and shared auth props", %{conn: conn, user: user, scope: scope} do
    conn = get(conn, ~p"/dashboard")
    assert inertia_component(conn) == "dashboard/show"
    auth = inertia_props(conn).auth
    assert auth.user["email"] == user.email
    assert auth.organization["id"] == scope.organization.id
    assert auth.membership["role"] == "owner"
    assert html_response(conn, 200) =~ ~s(name="robots" content="noindex")
  end

  test "appearance page renders", %{conn: conn} do
    assert conn |> get(~p"/settings/appearance/edit") |> inertia_component() ==
             "settings/appearance/edit"
  end
end
