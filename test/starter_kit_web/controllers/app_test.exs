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

  test "settings pages render", %{conn: conn} do
    for {path, component} <- [
          {~p"/settings/profile/edit", "settings/profile/edit"},
          {~p"/settings/appearance/edit", "settings/appearance/edit"},
          {~p"/settings/sessions", "settings/sessions/index"},
          {~p"/settings/email/edit", "settings/email/edit"},
          {~p"/settings/password/edit", "settings/password/edit"},
          {~p"/settings/account/edit", "settings/account/edit"}
        ] do
      assert conn |> get(path) |> inertia_component() == component
    end
  end

  test "profile update changes the language", %{conn: conn} do
    conn = patch(conn, ~p"/settings/profile", %{"user" => %{"name" => "Ana", "locale" => "es"}})
    assert redirected_to(conn) == ~p"/settings/profile/edit"
    assert conn |> recycle() |> get(~p"/dashboard") |> inertia_props() |> Map.get(:locale) == "es"
  end

  test "sensitive settings need a recent sign-in", %{conn: conn, user: user} do
    stale = %{user | authenticated_at: DateTime.add(DateTime.utc_now(:second), -3600)}
    token = StarterKit.Accounts.generate_user_session_token(stale)
    conn = conn |> put_session(:user_token, token) |> get(~p"/settings/password/edit")
    assert redirected_to(conn) == "http://localhost:5173/auth/session"
  end

  test "sessions page marks this device and can end another", %{conn: conn, user: user} do
    StarterKit.Accounts.generate_user_session_token(user, %{user_agent: "Other"})
    props = conn |> get(~p"/settings/sessions") |> inertia_props()
    assert length(props.sessions) == 2
    other = Enum.find(props.sessions, &(&1["id"] != props.currentSessionId))

    conn = delete(conn, ~p"/settings/sessions/#{other["id"]}")
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "signed out"
  end

  test "deleting the account signs out", %{conn: conn, user: user} do
    conn = delete(conn, ~p"/settings/account")
    assert redirected_to(conn) == ~p"/"
    refute StarterKit.Repo.get(StarterKit.Accounts.User, user.id)
  end

  test "the account page says what stops the deletion, and the deletion refuses",
       %{conn: conn, user: user, scope: scope} do
    membership_fixture(scope, user_fixture(), :member)

    props = conn |> get(~p"/settings/account/edit") |> inertia_props()
    assert %{reason: :transfer_ownership, organization: name} = props.blocker
    assert name == scope.organization.name

    conn = delete(conn, ~p"/settings/account")
    assert redirected_to(conn) == ~p"/settings/account/edit"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "owner"
    assert StarterKit.Repo.get(StarterKit.Accounts.User, user.id)
  end
end
