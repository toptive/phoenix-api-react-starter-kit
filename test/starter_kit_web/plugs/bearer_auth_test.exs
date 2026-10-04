defmodule StarterKitWeb.Plugs.BearerAuthTest do
  use StarterKitWeb.ConnCase, async: true
  alias StarterKit.Accounts
  alias StarterKit.Accounts.Scope
  alias StarterKitWeb.Plugs.BearerAuth

  test "missing, malformed, multiple and unsupported authorization headers are anonymous", %{
    conn: conn
  } do
    for headers <- [[], ["Basic abc"], ["Bearer !"], ["Bearer"], ["Bearer abc", "Bearer def"]] do
      result =
        %{conn | req_headers: Enum.map(headers, &{"authorization", &1})} |> BearerAuth.call([])

      assert result.assigns.current_user == nil
      assert result.assigns.current_scope == nil
      assert result.assigns.api_token == nil

      assert json_response(BearerAuth.require_authenticated_api_user(result, []), 401)["error"][
               "code"
             ] == "unauthorized"
    end
  end

  test "bearer auth loads scope, token and impersonator", %{conn: conn} do
    user = user_fixture()
    admin = superadmin_fixture()
    session = Accounts.generate_api_token(user, %{}, impersonator_id: admin.id)

    result =
      conn |> put_req_header("authorization", "bearer " <> session.token) |> BearerAuth.call([])

    assert result.assigns.current_user.id == user.id
    assert result.assigns.api_token.impersonator_id == admin.id
    assert result.assigns.current_scope.impersonator.id == admin.id
    assert result.assigns.current_scope.organization
    assert BearerAuth.require_authenticated_api_user(result, []) == result

    assert json_response(BearerAuth.require_superadmin(result, []), 404)["error"]["code"] ==
             "not_found"

    assert json_response(BearerAuth.require_sudo(result, []), 401)["error"]["code"] ==
             "sudo_required"
  end

  test "sudo and superadmin checks use token state", %{conn: conn} do
    admin = superadmin_fixture()
    session = Accounts.generate_api_token(admin)

    auth =
      conn |> put_req_header("authorization", "Bearer " <> session.token) |> BearerAuth.call([])

    assert BearerAuth.require_superadmin(auth, []) == auth
    assert BearerAuth.require_sudo(auth, []) == auth
    stale = put_in(auth.assigns.api_token.sudo_until, DateTime.add(DateTime.utc_now(:second), -1))

    assert json_response(BearerAuth.require_sudo(stale, []), 401)["error"]["code"] ==
             "sudo_required"

    assert json_response(BearerAuth.require_superadmin(BearerAuth.call(conn, []), []), 404)
    assert Scope.organization_id(auth.assigns.current_scope)
  end
end
