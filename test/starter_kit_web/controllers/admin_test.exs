defmodule StarterKitWeb.AdminTest do
  # Editing a translation reloads the global catalogue (a new i18n version): not async, or
  # a concurrent public page test sees two versions and its ETag check fails.
  use StarterKitWeb.ConnCase, async: false

  describe "as a normal user" do
    setup :register_and_log_in_user

    test "the admin area does not exist", %{conn: conn} do
      for path <- [~p"/admin", ~p"/admin/users", ~p"/admin/translations", ~p"/admin/oban"] do
        assert conn |> get(path) |> Map.get(:status) == 404
      end
    end
  end

  describe "as a superadmin" do
    setup :register_and_log_in_superadmin

    test "every admin page renders", %{conn: conn} do
      org = scope_fixture()
      user = org.user

      for {path, component} <- [
            {~p"/admin", "admin/dashboard/show"},
            {~p"/admin/users", "admin/users/index"},
            {~p"/admin/users/#{user.id}", "admin/users/show"},
            {~p"/admin/organizations", "admin/organizations/index"},
            {~p"/admin/organizations/#{org.organization.id}", "admin/organizations/show"},
            {~p"/admin/translations", "admin/translations/index"},
            {~p"/admin/legal-documents", "admin/legal-documents/index"},
            {~p"/admin/legal-documents/terms", "admin/legal-documents/show"},
            {~p"/admin/audit-events", "admin/audit-events/index"}
          ] do
        assert conn |> get(path) |> inertia_component() == component, path
      end
    end

    test "user search paginates", %{conn: conn} do
      target = user_fixture(name: "Zelda Findme")
      props = conn |> get(~p"/admin/users?q=findme") |> inertia_props()
      assert [%{"email" => email}] = props.users
      assert email == target.email
      assert props.pagination["total"] == 1
    end

    test "editing a translation", %{conn: conn} do
      StarterKit.I18n.sync()
      on_exit(&StarterKit.I18n.Catalog.reset_to_reference/0)

      conn =
        put(conn, ~p"/admin/translations/nav.home", %{
          "translation" => %{"locale" => "es", "value" => "Portada"}
        })

      assert redirected_to(conn) =~ "/admin/translations"
      assert StarterKit.I18n.t("nav.home", %{}, "es") == "Portada"
    end

    test "publishing a legal version", %{conn: conn} do
      conn =
        post(conn, ~p"/admin/legal-documents/privacy/versions", %{
          "version" => %{
            "titles" => %{"en" => "Privacy"},
            "bodies" => %{"en" => "We care."},
            "publish" => "true"
          }
        })

      assert redirected_to(conn) == ~p"/admin/legal-documents/privacy"
      assert {:ok, %{title: "Privacy"}} = StarterKit.Legal.published_page("privacy", "en")
    end

    test "starting an impersonation", %{conn: conn, user: admin} do
      target = user_fixture()
      scope_fixture(target)

      conn =
        post(conn, ~p"/admin/users/#{target.id}/impersonation", %{
          "impersonation" => %{"reason" => "Ticket 42"}
        })

      assert redirected_to(conn) == ~p"/dashboard"

      props = conn |> recycle() |> get(~p"/dashboard") |> inertia_props()
      assert props.auth.user["id"] == target.id
      assert props.auth.impersonator["id"] == admin.id
      refute props.auth.superadmin
    end
  end
end
