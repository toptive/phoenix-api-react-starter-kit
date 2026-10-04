defmodule StarterKitWeb.AppTest do
  use StarterKitWeb.ConnCase, async: true

  import Swoosh.TestAssertions

  alias StarterKit.Organizations
  alias StarterKit.Organizations.Organization

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
          {~p"/settings/organization/edit", "settings/organization/edit"},
          {~p"/settings/members", "settings/members/index"},
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

  test "inviting someone and listing them as pending", %{conn: conn} do
    conn =
      post(conn, ~p"/settings/invitations", %{
        "invitation" => %{"email" => "new@example.com", "role" => "member", "access" => "viewer"}
      })

    assert redirected_to(conn) == ~p"/settings/members"
    assert_email_sent(subject: "Test User invited you to Test User")

    [invitation] =
      conn |> recycle() |> get(~p"/settings/members") |> inertia_props() |> Map.get(:invitations)

    assert invitation["email"] == "new@example.com"
    assert invitation["access"] == "viewer"
  end

  test "a viewer member cannot invite or manage people", %{conn: conn, scope: scope} do
    viewer = user_fixture()
    membership_fixture(scope, viewer, :member, :viewer)
    conn = conn |> log_in_user(viewer) |> put_session(:organization_id, scope.organization.id)

    props = conn |> get(~p"/settings/members") |> inertia_props()
    refute props.canManage
    assert props.invitations == []

    conn = post(conn, ~p"/settings/invitations", %{"invitation" => %{"email" => "x@example.com"}})
    assert inertia_component(conn) == "errors/show"
    assert conn.status == 403
  end

  test "switching organization", %{conn: conn, user: user} do
    other = scope_fixture()
    membership_fixture(other, user)

    conn = patch(conn, ~p"/current-organization", %{"organizationId" => other.organization.id})
    assert redirected_to(conn) == ~p"/dashboard"
    props = conn |> recycle() |> get(~p"/dashboard") |> inertia_props()
    assert props.auth.organization["id"] == other.organization.id
  end

  test "cannot switch into a foreign organization", %{conn: conn} do
    other = scope_fixture()
    conn = patch(conn, ~p"/current-organization", %{"organizationId" => other.organization.id})
    assert conn.status == 403
  end

  test "creating another organization", %{conn: conn} do
    conn = post(conn, ~p"/organizations", %{"organization" => %{"name" => "Acme"}})
    assert redirected_to(conn) == ~p"/dashboard"
    props = conn |> recycle() |> get(~p"/dashboard") |> inertia_props()
    assert props.auth.organization["name"] == "Acme"
    assert length(props.auth.organizations) == 2
  end

  test "accepting an invitation from its page", %{conn: conn, user: user} do
    other = scope_fixture()
    token = capture_token(&Organizations.create_invitation(other, %{"email" => user.email}, &1))

    page = get(conn, ~p"/invitations/#{token}")
    assert inertia_props(page).emailMatches

    conn = post(conn, ~p"/invitations/#{token}/acceptance")
    assert redirected_to(conn) == ~p"/dashboard"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Welcome"
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

  test "a new organization's owner goes through onboarding once", %{conn: conn, scope: scope} do
    scope.organization |> Ecto.Changeset.change(onboarded_at: nil) |> StarterKit.Repo.update!()

    assert conn |> get(~p"/dashboard") |> redirected_to() == ~p"/onboarding/edit"

    page = get(conn, ~p"/onboarding/edit")
    assert inertia_component(page) == "onboarding/edit"
    assert inertia_props(page).organizationName == scope.organization.name

    done = patch(conn, ~p"/onboarding", %{"onboarding" => %{"name" => "Acme"}})
    assert redirected_to(done) == ~p"/dashboard"

    assert_received {:analytics,
                     %{event: "onboarding_completed", properties: %{"skipped" => false}}}

    assert conn |> get(~p"/dashboard") |> inertia_component() == "dashboard/show"
    assert conn |> get(~p"/onboarding/edit") |> redirected_to() == ~p"/dashboard"
    assert StarterKit.Repo.get!(Organization, scope.organization.id).name == "Acme"
  end
end
