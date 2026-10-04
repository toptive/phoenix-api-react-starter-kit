defmodule StarterKitWeb.ApiOrganizationsTest do
  use StarterKitWeb.ConnCase, async: true
  import Ecto.Query
  import StarterKitWeb.ApiHelpers
  alias StarterKit.{Accounts, Repo}
  alias StarterKit.Organizations.{Invitation, Membership, Organization}

  setup %{conn: conn} do
    conn = api_conn(conn)
    user = user_fixture(password: "correct horse battery")
    scope = scope_fixture(user, onboarded: false)
    session = sign_in(conn, user)
    %{conn: conn, user: user, scope: scope, session: session, auth: bearer(conn, session["token"])}
  end

  test "every private tenancy endpoint requires bearer authentication", ctx do
    id = ctx.scope.membership.id
    invitation_id = Ecto.UUID.generate()

    for {method, path} <- [
          {:put, "/api/v1/current-organization"},
          {:post, "/api/v1/organizations"},
          {:get, "/api/v1/onboarding"},
          {:put, "/api/v1/onboarding"},
          {:post, "/api/v1/invitations/token/acceptance"},
          {:get, "/api/v1/settings/organization"},
          {:put, "/api/v1/settings/organization"},
          {:get, "/api/v1/settings/members"},
          {:put, "/api/v1/settings/members/#{id}"},
          {:delete, "/api/v1/settings/members/#{id}"},
          {:get, "/api/v1/settings/invitations"},
          {:post, "/api/v1/settings/invitations"},
          {:delete, "/api/v1/settings/invitations/#{invitation_id}"}
        ] do
      assert_error(dispatch(ctx.conn, @endpoint, method, path, %{}), 401, "unauthorized")
    end
  end

  test "organization creation returns Organization and switches just this device", ctx do
    other_session = sign_in(ctx.conn, ctx.user)

    created =
      post(ctx.auth, ~p"/api/v1/organizations", %{name: "Acme", ignored: "value"})
      |> json_response(201)
      |> Map.fetch!("data")

    assert Map.keys(created) |> Enum.sort() == ~w(id name personal slug)
    assert created["name"] == "Acme"
    refute created["personal"]
    assert current_auth(ctx.auth)["organization"]["id"] == created["id"]
    refute current_auth(ctx.auth)["onboardingRequired"]

    assert current_auth(bearer(ctx.conn, other_session["token"]))["organization"]["id"] ==
             ctx.scope.organization.id

    newest = sign_in(ctx.conn, ctx.user)
    assert current_auth(bearer(ctx.conn, newest["token"]))["organization"]["id"] == created["id"]
    assert_received {:analytics, %{event: "organization_created"}}
  end

  test "organization creation validates length with translated bindings", ctx do
    response = post(ctx.auth, ~p"/api/v1/organizations", %{name: "A"})
    errors = assert_field(response, "name", "validation.length_min")
    assert hd(errors)["bindings"] == %{"count" => 2}

    assert_field(
      post(ctx.auth, ~p"/api/v1/organizations", %{name: String.duplicate("x", 81)}),
      "name",
      "validation.length_max"
    )

    assert_field(post(ctx.auth, ~p"/api/v1/organizations", %{}), "name", "validation.required")

    assert_error(
      post(ctx.auth, ~p"/api/v1/organizations", %{name: %{unexpected: true}}),
      400,
      "bad_request"
    )

    assert Repo.aggregate(Organization, :count) == 1
  end

  test "switching returns Auth, persists on user and device, and cannot cross membership boundaries",
       ctx do
    other = scope_fixture()

    assert_error(
      put(ctx.auth, ~p"/api/v1/current-organization", %{organizationId: other.organization.id}),
      409,
      "not_member"
    )

    assert_error(
      put(ctx.auth, ~p"/api/v1/current-organization", %{organizationId: "bad"}),
      409,
      "not_member"
    )

    assert_error(put(ctx.auth, ~p"/api/v1/current-organization", %{}), 400, "bad_request")

    assert_error(
      put(ctx.auth, ~p"/api/v1/current-organization", %{organizationId: 3}),
      400,
      "bad_request"
    )

    membership_fixture(other, ctx.user)
    other_session = sign_in(ctx.conn, ctx.user)

    response =
      put(ctx.auth, ~p"/api/v1/current-organization", %{organizationId: other.organization.id})
      |> json_response(200)

    assert response["data"]["organization"]["id"] == other.organization.id
    assert response["data"]["membership"]["user"] == nil
    assert Accounts.get_user!(ctx.user.id).last_organization_id == other.organization.id
    assert current_auth(ctx.auth)["organization"]["id"] == other.organization.id

    assert current_auth(bearer(ctx.conn, other_session["token"]))["organization"]["id"] ==
             ctx.scope.organization.id
  end

  test "onboarding GET and PUT validate, keep blank answers and report completion", ctx do
    assert json_response(get(ctx.auth, ~p"/api/v1/onboarding"), 200)["data"] == %{
             "organizationName" => ctx.scope.organization.name,
             "required" => true
           }

    assert_field(
      put(ctx.auth, ~p"/api/v1/onboarding", %{name: "A"}),
      "name",
      "validation.length_min"
    )

    done = put(ctx.auth, ~p"/api/v1/onboarding", %{name: "   "}) |> json_response(200)
    assert done["data"]["name"] == ctx.scope.organization.name
    refute json_response(get(ctx.auth, ~p"/api/v1/onboarding"), 200)["data"]["required"]
    refute current_auth(ctx.auth)["onboardingRequired"]
    assert_received {:analytics, %{event: "onboarding_completed", properties: %{"skipped" => true}}}

    assert json_response(put(ctx.auth, ~p"/api/v1/onboarding", %{name: "Team"}), 200)["data"][
             "name"
           ] == "Team"
  end

  test "members and viewer admins read settings and members, but cannot manage or onboard", ctx do
    for {role, access} <- [{:member, :full}, {:admin, :viewer}] do
      user = user_fixture(password: "correct horse battery")
      membership_fixture(ctx.scope, user, role, access)
      auth = member_conn(ctx.conn, user, ctx.scope.organization.id)

      assert json_response(get(auth, ~p"/api/v1/settings/organization"), 200)["data"]["canEdit"] ==
               false

      assert json_response(get(auth, ~p"/api/v1/settings/members"), 200)["data"] != []

      for response <- [
            get(auth, ~p"/api/v1/onboarding"),
            put(auth, ~p"/api/v1/onboarding", %{}),
            put(auth, ~p"/api/v1/settings/organization", %{name: "No"}),
            get(auth, ~p"/api/v1/settings/invitations"),
            post(auth, ~p"/api/v1/settings/invitations", %{email: unique_email()}),
            put(auth, ~p"/api/v1/settings/members/#{ctx.scope.membership.id}", %{role: "member"}),
            delete(auth, ~p"/api/v1/settings/members/#{ctx.scope.membership.id}")
          ],
          do: assert_error(response, 403, "forbidden")
    end
  end

  test "organization settings GET and PUT apply only to the current tenant", ctx do
    other = scope_fixture()
    data = json_response(get(ctx.auth, ~p"/api/v1/settings/organization"), 200)["data"]
    assert data["canEdit"]
    assert data["organization"]["id"] == ctx.scope.organization.id

    assert_field(
      put(ctx.auth, ~p"/api/v1/settings/organization", %{name: "A"}),
      "name",
      "validation.length_min"
    )

    response =
      put(ctx.auth, ~p"/api/v1/settings/organization", %{
        name: "Renamed",
        organizationId: other.organization.id
      })
      |> json_response(200)

    assert response["data"]["name"] == "Renamed"
    assert Repo.reload!(other.organization).name == other.organization.name
    assert current_auth(ctx.auth)["organization"]["name"] == "Renamed"
  end

  test "member list includes users, follows membership insertion and excludes other tenants", ctx do
    member = membership_fixture(ctx.scope, user_fixture())
    other = scope_fixture()
    members = json_response(get(ctx.auth, ~p"/api/v1/settings/members"), 200)["data"]
    assert length(members) == 2
    assert Enum.all?(members, &is_map(&1["user"]))
    assert Enum.any?(members, &(&1["id"] == member.id))
    refute Enum.any?(members, &(&1["id"] == other.membership.id))
  end

  test "owners update role and access; enums, owner-only changes and last-owner demotion validate",
       ctx do
    member = membership_fixture(ctx.scope, user_fixture())

    response =
      put(ctx.auth, ~p"/api/v1/settings/members/#{member.id}", %{role: "owner", access: "full"})
      |> json_response(200)

    assert response["data"]["role"] == "owner"
    assert response["data"]["user"]["id"] == member.user_id

    assert_field(
      put(ctx.auth, ~p"/api/v1/settings/members/#{member.id}", %{role: "bad"}),
      "role",
      "validation.inclusion"
    )

    assert_field(
      put(ctx.auth, ~p"/api/v1/settings/members/#{member.id}", %{access: "bad"}),
      "access",
      "validation.inclusion"
    )

    # A second owner lets the first owner be demoted.
    assert json_response(
             put(ctx.auth, ~p"/api/v1/settings/members/#{ctx.scope.membership.id}", %{role: "admin"}),
             200
           )

    assert_field(
      put(ctx.auth, ~p"/api/v1/settings/members/#{member.id}", %{role: "member"}),
      "role",
      "validation.owner_only"
    )
  end

  test "last-owner demotion is a field validation; last-owner leave is a 409 flow", ctx do
    assert_field(
      put(ctx.auth, ~p"/api/v1/settings/members/#{ctx.scope.membership.id}", %{role: "member"}),
      "role",
      "validation.last_owner"
    )

    assert_error(
      delete(ctx.auth, ~p"/api/v1/settings/members/#{ctx.scope.membership.id}"),
      409,
      "last_owner"
    )

    assert current_auth(ctx.auth)["membership"]["role"] == "owner"
    assert Repo.get!(Membership, ctx.scope.membership.id, org_id: ctx.scope.organization.id)
  end

  test "admins may change members, but changing an owner validates and removing one is forbidden",
       ctx do
    admin = user_fixture(password: "correct horse battery")
    membership_fixture(ctx.scope, admin, :admin)
    member = membership_fixture(ctx.scope, user_fixture())
    auth = member_conn(ctx.conn, admin, ctx.scope.organization.id)

    assert json_response(
             put(auth, ~p"/api/v1/settings/members/#{member.id}", %{access: "viewer"}),
             200
           )["data"]["access"] == "viewer"

    assert_field(
      put(auth, ~p"/api/v1/settings/members/#{member.id}", %{role: "owner"}),
      "role",
      "validation.owner_only"
    )

    assert_field(
      put(auth, ~p"/api/v1/settings/members/#{ctx.scope.membership.id}", %{access: "viewer"}),
      "role",
      "validation.owner_only"
    )

    assert_error(
      delete(auth, ~p"/api/v1/settings/members/#{ctx.scope.membership.id}"),
      403,
      "forbidden"
    )

    assert response(delete(auth, ~p"/api/v1/settings/members/#{member.id}"), 204) == ""
  end

  test "member removal is tenant scoped; a member may leave and the device falls back", ctx do
    other = scope_fixture()

    for id <- [other.membership.id, Ecto.UUID.generate(), "bad"] do
      assert_error(
        put(ctx.auth, "/api/v1/settings/members/#{id}", %{role: "admin"}),
        404,
        "not_found"
      )

      assert_error(delete(ctx.auth, "/api/v1/settings/members/#{id}"), 404, "not_found")
    end

    user = user_fixture(password: "correct horse battery")
    home = scope_fixture(user)
    member = membership_fixture(ctx.scope, user)
    auth = member_conn(ctx.conn, user, ctx.scope.organization.id)
    assert response(delete(auth, ~p"/api/v1/settings/members/#{member.id}"), 204) == ""
    assert current_auth(auth)["organization"]["id"] == home.organization.id
    assert Accounts.get_user!(user.id).last_organization_id == home.organization.id
  end

  test "leaving the only organization creates a new personal organization when another owner remains",
       ctx do
    membership_fixture(ctx.scope, user_fixture(), :owner)

    assert response(delete(ctx.auth, ~p"/api/v1/settings/members/#{ctx.scope.membership.id}"), 204) ==
             ""

    auth = current_auth(ctx.auth)
    assert auth["organization"]["personal"]
    refute auth["organization"]["id"] == ctx.scope.organization.id
    assert auth["membership"]["role"] == "owner"
  end

  test "invitation creation, listing and revocation use the current org and request locale", ctx do
    email = unique_email()

    invitation =
      ctx.auth
      |> put_req_header("accept-language", "es")
      |> post(~p"/api/v1/settings/invitations", %{email: email, role: "admin", access: "viewer"})
      |> json_response(201)
      |> Map.fetch!("data")

    assert invitation["email"] == email
    refute Map.has_key?(invitation, "token")
    assert_receive {:email, mail}
    assert mail.subject =~ "invitó"
    [_, token] = Regex.run(~r{/invitations/([a-zA-Z0-9_-]+)}, mail.text_body)
    preview = get(ctx.conn, ~p"/api/v1/invitations/#{token}") |> json_response(200)
    assert preview["data"]["organization"] == ctx.scope.organization.name
    assert preview["data"]["role"] == "admin"
    refute preview["data"]["emailMatches"]

    assert json_response(get(ctx.auth, ~p"/api/v1/settings/invitations"), 200)["data"] == [
             invitation
           ]

    assert response(delete(ctx.auth, ~p"/api/v1/settings/invitations/#{invitation["id"]}"), 204) ==
             ""

    assert json_response(get(ctx.auth, ~p"/api/v1/settings/invitations"), 200)["data"] == []
    assert_error(get(ctx.conn, ~p"/api/v1/invitations/#{token}"), 422, "invitation_invalid")
  end

  test "invitations validate email, pending duplicates, member addresses, owner role and enums",
       ctx do
    for {params, field, key} <- [
          {%{email: "invalid"}, "email", "validation.email_format"},
          {%{email: ctx.user.email}, "email", "validation.already_member"},
          {%{email: unique_email(), role: "owner"}, "role", "validation.invitation_owner"},
          {%{email: unique_email(), role: "unknown"}, "role", "validation.inclusion"},
          {%{email: unique_email(), access: "unknown"}, "access", "validation.inclusion"}
        ],
        do: assert_field(post(ctx.auth, ~p"/api/v1/settings/invitations", params), field, key)

    email = unique_email()
    assert json_response(post(ctx.auth, ~p"/api/v1/settings/invitations", %{email: email}), 201)

    assert_field(
      post(ctx.auth, ~p"/api/v1/settings/invitations", %{email: String.upcase(email)}),
      "email",
      "validation.invitation_pending"
    )
  end

  test "invitation list and delete cannot cross tenants or return expired invitations", ctx do
    other = scope_fixture(user_fixture(password: "correct horse battery"))
    other_auth = bearer(ctx.conn, sign_in(ctx.conn, other.user)["token"])

    foreign =
      post(other_auth, ~p"/api/v1/settings/invitations", %{email: unique_email()})
      |> json_response(201)

    email_token("/invitations/")
    assert json_response(get(ctx.auth, ~p"/api/v1/settings/invitations"), 200)["data"] == []

    assert_error(
      delete(ctx.auth, ~p"/api/v1/settings/invitations/#{foreign["data"]["id"]}"),
      404,
      "not_found"
    )

    assert_error(delete(ctx.auth, "/api/v1/settings/invitations/bad"), 404, "not_found")
    invitee_email = unique_email()

    own =
      post(ctx.auth, ~p"/api/v1/settings/invitations", %{email: invitee_email})
      |> json_response(201)

    expired_token = email_token("/invitations/")

    Repo.update_all(
      from(i in Invitation, where: i.id == ^own["data"]["id"]),
      [set: [expires_at: DateTime.add(DateTime.utc_now(:second), -1)]],
      org_id: ctx.scope.organization.id
    )

    assert json_response(get(ctx.auth, ~p"/api/v1/settings/invitations"), 200)["data"] == []
    assert_error(get(ctx.conn, ~p"/api/v1/invitations/#{expired_token}"), 422, "invitation_invalid")

    assert_error(
      post(ctx.auth, ~p"/api/v1/invitations/#{expired_token}/acceptance", %{}),
      422,
      "invitation_invalid"
    )

    assert json_response(
             post(ctx.auth, ~p"/api/v1/settings/invitations", %{email: invitee_email}),
             201
           )

    member = user_fixture(password: "correct horse battery")
    membership_fixture(ctx.scope, member)
    member_auth = member_conn(ctx.conn, member, ctx.scope.organization.id)

    assert_error(
      delete(member_auth, ~p"/api/v1/settings/invitations/#{foreign["data"]["id"]}"),
      403,
      "forbidden"
    )
  end

  test "invitation preview and acceptance reject unknown, expired, accepted and mismatched tokens",
       ctx do
    invitee = user_fixture(password: "correct horse battery")

    invitation =
      post(ctx.auth, ~p"/api/v1/settings/invitations", %{
        email: invitee.email,
        role: "member",
        access: "viewer"
      })
      |> json_response(201)
      |> Map.fetch!("data")

    token = email_token("/invitations/")
    assert_error(get(ctx.conn, ~p"/api/v1/invitations/!"), 422, "invitation_invalid")

    assert_error(
      post(ctx.auth, ~p"/api/v1/invitations/!/acceptance", %{}),
      422,
      "invitation_invalid"
    )

    details =
      assert_error(
        post(ctx.auth, ~p"/api/v1/invitations/#{token}/acceptance", %{}),
        409,
        "email_mismatch"
      )

    assert details == %{"email" => invitee.email}
    auth = bearer(ctx.conn, sign_in(ctx.conn, invitee)["token"])
    assert json_response(get(auth, ~p"/api/v1/invitations/#{token}"), 200)["data"]["emailMatches"]
    accepted = post(auth, ~p"/api/v1/invitations/#{token}/acceptance", %{}) |> json_response(201)
    assert accepted["data"]["user"]["id"] == invitee.id
    assert accepted["data"]["access"] == "viewer"
    assert current_auth(auth)["organization"]["id"] == ctx.scope.organization.id
    assert_error(get(ctx.conn, ~p"/api/v1/invitations/#{token}"), 422, "invitation_invalid")

    assert_error(
      post(auth, ~p"/api/v1/invitations/#{token}/acceptance", %{}),
      422,
      "invitation_invalid"
    )

    assert Repo.get!(Invitation, invitation["id"], org_id: ctx.scope.organization.id).accepted_at
    assert_received {:analytics, %{event: "invitation_accepted"}}
  end

  test "accepting for an existing member keeps their membership and returns its persisted id",
       ctx do
    invitee = user_fixture(password: "correct horse battery")

    assert json_response(
             post(ctx.auth, ~p"/api/v1/settings/invitations", %{email: invitee.email}),
             201
           )

    token = email_token("/invitations/")
    membership = membership_fixture(ctx.scope, invitee, :admin)
    auth = bearer(ctx.conn, sign_in(ctx.conn, invitee)["token"])
    accepted = post(auth, ~p"/api/v1/invitations/#{token}/acceptance", %{}) |> json_response(201)
    assert accepted["data"]["id"] == membership.id
    assert accepted["data"]["role"] == "admin"
    assert Repo.aggregate(Membership, :count, org_id: ctx.scope.organization.id) == 2
  end

  test "invitations enforce plan capacity including reserved seats", ctx do
    for _ <- 1..2 do
      assert json_response(
               post(ctx.auth, ~p"/api/v1/settings/invitations", %{email: unique_email()}),
               201
             )
    end

    errors =
      assert_field(
        post(ctx.auth, ~p"/api/v1/settings/invitations", %{email: unique_email()}),
        "email",
        "validation.limit_reached"
      )

    assert hd(errors)["bindings"] == %{"limit" => 3}
    assert Repo.aggregate(Invitation, :count, org_id: ctx.scope.organization.id) == 2
  end

  test "invitations create and acceptance have their contract rate limits", ctx do
    for _ <- 1..30, do: post(ctx.auth, ~p"/api/v1/settings/invitations", %{email: "invalid"})

    assert_error(
      post(ctx.auth, ~p"/api/v1/settings/invitations", %{email: "invalid"}),
      429,
      "rate_limited"
    )

    for _ <- 1..10, do: post(ctx.auth, ~p"/api/v1/invitations/!/acceptance", %{})
    assert_error(post(ctx.auth, ~p"/api/v1/invitations/!/acceptance", %{}), 429, "rate_limited")
  end

  test "register → confirm → sign in → create org → invite → accept as another user → list members",
       %{conn: conn} do
    email = unique_email()

    assert json_response(
             post(conn, ~p"/api/v1/auth/registrations", %{
               name: "Ana",
               email: email,
               termsAccepted: true
             }),
             202
           )

    token = email_token("/auth/magic-links/")

    assert json_response(get(conn, ~p"/api/v1/auth/magic-links/#{token}"), 200)["data"]["confirmed"] ==
             false

    confirmation =
      post(conn, ~p"/api/v1/auth/magic-links/#{token}/session", %{}) |> json_response(201)

    assert confirmation["data"]["newAccount"]

    assert response(
             delete(bearer(conn, confirmation["data"]["token"]), ~p"/api/v1/auth/session"),
             204
           ) == ""

    signin_token = request_magic(conn, email)

    signed_in =
      post(conn, ~p"/api/v1/auth/magic-links/#{signin_token}/session", %{}) |> json_response(201)

    owner = bearer(conn, signed_in["data"]["token"])
    org = post(owner, ~p"/api/v1/organizations", %{name: "Flow team"}) |> json_response(201)
    invitee_email = unique_email()

    assert json_response(
             post(owner, ~p"/api/v1/settings/invitations", %{
               email: invitee_email,
               role: "member",
               access: "full"
             }),
             201
           )

    invitation_token = email_token("/invitations/")

    assert json_response(
             post(conn, ~p"/api/v1/auth/registrations", %{
               name: "Bob",
               email: invitee_email,
               termsAccepted: true
             }),
             202
           )

    invitee_token = email_token("/auth/magic-links/")

    invitee_session =
      post(conn, ~p"/api/v1/auth/magic-links/#{invitee_token}/session", %{}) |> json_response(201)

    invitee = bearer(conn, invitee_session["data"]["token"])

    assert json_response(
             post(invitee, ~p"/api/v1/invitations/#{invitation_token}/acceptance", %{}),
             201
           )

    assert current_auth(invitee)["organization"]["id"] == org["data"]["id"]
    members = get(invitee, ~p"/api/v1/settings/members") |> json_response(200)

    assert Enum.map(members["data"], & &1["user"]["email"]) |> Enum.sort() ==
             Enum.sort([email, invitee_email])
  end

  defp member_conn(conn, user, org_id) do
    auth = bearer(conn, sign_in(conn, user)["token"])

    assert json_response(
             put(auth, ~p"/api/v1/current-organization", %{organizationId: org_id}),
             200
           )

    auth
  end
end
