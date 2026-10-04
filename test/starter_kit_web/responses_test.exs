defmodule StarterKitWeb.ResponsesTest do
  use StarterKitWeb.ConnCase, async: true
  alias StarterKitWeb.{ErrorPages, Responses, Serializers}

  defmodule DeniedController do
    def show(_conn, _params),
      do: raise(StarterKitWeb.NotAuthorizedError, action: :show, resource: StarterKit.Accounts.User)
  end

  defmodule MissingController do
    def show(_conn, _params), do: raise(Ecto.NoResultsError, queryable: StarterKit.Accounts.User)
  end

  test "success always includes meta and camelizes identifier keys", %{conn: conn} do
    result =
      Responses.render_data(
        conn,
        %{created_at: "today", translations: %{"nav.home" => "Home", "zh-HK" => "x"}},
        %{total_pages: 2}
      )

    assert json_response(result, 200) == %{
             "data" => %{
               "createdAt" => "today",
               "translations" => %{"nav.home" => "Home", "zh-HK" => "x"}
             },
             "meta" => %{"totalPages" => 2}
           }

    assert json_response(Responses.render_data(conn, nil), 200) == %{"data" => nil, "meta" => %{}}
  end

  test "serializers and collections share the envelope", %{conn: conn} do
    user = user_fixture()

    assert json_response(Responses.render_data(conn, {Serializers.UserSerializer, user}), 200)[
             "data"
           ]["id"] == user.id

    assert %{"data" => [%{"id" => id}], "meta" => %{"perPage" => 10}} =
             json_response(
               Responses.render_collection(conn, [user], Serializers.UserSerializer, %{per_page: 10}),
               200
             )

    assert id == user.id
  end

  test "error messages are translated while validation details remain keys", %{conn: conn} do
    conn = assign(conn, :locale, "es")
    result = Responses.render_error(conn, 401, :unauthorized)
    assert json_response(result, 401)["error"]["message"] == "Ingresá para continuar."
    changeset = StarterKit.Accounts.change_registration(%{email: "x"})
    result = Responses.render_validation_error(conn, changeset)
    assert json_response(result, 422)["error"]["details"]["email"] == ["validation.email_format"]
  end

  test "ErrorPages converts policy denial and missing records to API envelopes", %{conn: conn} do
    conn = %{conn | request_path: "/api/v1/test", params: %{}}

    for {controller, status, code} <- [
          {DeniedController, 403, "forbidden"},
          {MissingController, 404, "not_found"}
        ] do
      result = ErrorPages.call_action(conn, controller, :show)
      assert json_response(result, status)["error"]["code"] == code
      assert result.private.authorized
    end
  end
end
