defmodule StarterKitWeb.ApiAdminTest do
  use StarterKitWeb.ConnCase, async: false
  import Ecto.Query
  import StarterKitWeb.ApiHelpers
  alias StarterKit.{Accounts, Audit, I18n, Repo}
  alias StarterKit.Accounts.{Impersonation, Session, User}
  alias StarterKit.I18n.Translation

  setup %{conn: conn} do
    conn = api_conn(conn)
    admin = superadmin_fixture(password: "correct horse battery")
    session = sign_in(conn, admin)
    on_exit(&I18n.Catalog.reset_to_reference/0)
    %{conn: conn, admin: admin, session: session, auth: bearer(conn, session["token"])}
  end

  for {method, path} <- [
        {:get, "/dashboard"},
        {:get, "/users"},
        {:get, "/users/unknown"},
        {:put, "/users/unknown"},
        {:post, "/users/unknown/impersonation"},
        {:get, "/organizations"},
        {:get, "/organizations/unknown"},
        {:get, "/translations"},
        {:put, "/translations/nav.home"},
        {:post, "/translation-fills"},
        {:get, "/legal-documents"},
        {:get, "/legal-documents/terms"},
        {:post, "/legal-documents/terms/versions"},
        {:post, "/legal-documents/terms/versions/1/publication"},
        {:get, "/audit-events"},
        {:post, "/jobs-access"}
      ],
      caller <- [:anonymous, :user, :impersonating, :expired] do
    @method method
    @path "/api/v1/admin" <> path
    @caller caller
    test "#{method} #{path} is hidden from #{caller}", %{conn: conn, admin: admin} do
      conn = hidden_caller(conn, admin, @caller)

      assert_error(
        Phoenix.ConnTest.dispatch(conn, @endpoint, @method, @path, %{}),
        404,
        "not_found"
      )
    end
  end

  test "dashboard returns counts", %{auth: auth} do
    data = get(auth, ~p"/api/v1/admin/dashboard") |> json_response(200) |> Map.fetch!("data")

    assert data == %{
             "users" => Repo.aggregate(User, :count),
             "organizations" => Repo.aggregate(StarterKit.Organizations.Organization, :count)
           }
  end

  test "users search names and emails without case sensitivity and paginate newest first", %{
    auth: auth
  } do
    target = user_fixture(name: "Zelda Searchable")
    old = user_fixture(name: "Zelda Older")

    Repo.update!(
      Ecto.Changeset.change(old, inserted_at: DateTime.add(DateTime.utc_now(:second), -60))
    )

    result = get(auth, ~p"/api/v1/admin/users?q=ZELDA&perPage=1") |> json_response(200)
    assert [%{"id" => id}] = result["data"]
    assert id == target.id

    assert result["meta"]["pagination"] == %{
             "page" => 1,
             "perPage" => 1,
             "total" => 2,
             "totalPages" => 2
           }

    assert [%{"id" => id}] =
             json_response(get(auth, ~p"/api/v1/admin/users?q=zelda&perPage=1&page=2"), 200)["data"]

    assert id == old.id

    assert [%{"id" => id}] =
             json_response(get(auth, ~p"/api/v1/admin/users?q=#{String.upcase(target.email)}"), 200)[
               "data"
             ]

    assert id == target.id
  end

  test "user detail includes organizations from every tenant", %{auth: auth} do
    scope = scope_fixture()

    data =
      get(auth, ~p"/api/v1/admin/users/#{scope.user.id}")
      |> json_response(200)
      |> Map.fetch!("data")

    assert data["user"]["id"] == scope.user.id
    assert Enum.any?(data["organizations"], &(&1["id"] == scope.organization.id))
  end

  for path <- ["users", "organizations"] do
    @path path
    test "#{path} show returns 404 for malformed or missing identifiers", %{auth: auth} do
      for id <- ["unknown", Ecto.UUID.generate()] do
        assert_error(get(auth, "/api/v1/admin/#{@path}/#{id}"), 404, "not_found")
      end
    end
  end

  test "role update changes only role and audits from/to", %{auth: auth, admin: admin} do
    user = user_fixture()

    assert json_response(
             put(auth, ~p"/api/v1/admin/users/#{user.id}", %{role: "superadmin", name: "Ignored"}),
             200
           )["data"]["role"] == "superadmin"

    assert Repo.reload!(user).name == user.name
    [event] = events("user.role_changed")
    assert event.actor_id == admin.id
    assert event.subject_id == user.id
    assert event.metadata == %{"from" => "user", "to" => "superadmin"}
  end

  test "role update validates missing/invalid role and missing users", %{auth: auth} do
    user = user_fixture()
    assert_field(put(auth, ~p"/api/v1/admin/users/#{user.id}", %{}), "role", "validation.required")

    assert_field(
      put(auth, ~p"/api/v1/admin/users/#{user.id}", %{role: "owner"}),
      "role",
      "validation.inclusion"
    )

    assert_error(put(auth, ~p"/api/v1/admin/users/unknown", %{role: "user"}), 404, "not_found")
    assert events("user.role_changed") == []
  end

  test "impersonate → act as user → stop → original admin session", %{
    conn: conn,
    auth: auth,
    admin: admin,
    session: original
  } do
    target = user_fixture()
    scope_fixture(target)

    issued =
      post(auth, ~p"/api/v1/admin/users/#{target.id}/impersonation", %{reason: "Support ticket 42"})
      |> json_response(201)
      |> Map.fetch!("data")

    assert issued["user"]["id"] == target.id
    assert issued["impersonator"]["id"] == admin.id
    assert issued["sudoUntil"] == nil
    refute issued["newAccount"]
    session = Repo.get_by!(Session, token_hash: :crypto.hash(:sha256, issued["token"]))
    assert session.impersonator_user_id == admin.id

    assert session.impersonator_session_id ==
             Repo.get_by!(Session, token_hash: :crypto.hash(:sha256, original["token"])).id

    assert DateTime.diff(session.expires_at, session.inserted_at) == 8 * 3600
    impersonation = Repo.get!(Impersonation, session.impersonation_id)
    assert impersonation.reason == "Support ticket 42"
    [event] = events("impersonation.started")

    assert event.metadata == %{
             "reason" => "Support ticket 42",
             "impersonationId" => impersonation.id
           }

    acting = bearer(conn, issued["token"])
    bootstrap = current_auth(acting)
    refute bootstrap["superadmin"]
    assert bootstrap["impersonator"]["id"] == admin.id

    assert json_response(
             put(acting, ~p"/api/v1/settings/email-preferences", %{optionalEmails: false}),
             200
           )

    [event] = events("user.optional_emails_stopped")
    assert event.actor_id == target.id and event.impersonator_id == admin.id
    assert response(delete(acting, ~p"/api/v1/auth/impersonation"), 204) == ""
    assert Repo.reload!(impersonation).ended_at
    assert_error(get(acting, ~p"/api/v1/bootstrap"), 401, "session_expired")
    assert current_auth(auth)["user"]["id"] == admin.id
    assert json_response(get(auth, ~p"/api/v1/admin/dashboard"), 200)
    assert length(events("impersonation.stopped")) == 1
  end

  test "impersonation refuses self and other superadmins", %{auth: auth, admin: admin} do
    for target <- [admin, superadmin_fixture()] do
      assert_error(
        post(auth, ~p"/api/v1/admin/users/#{target.id}/impersonation", %{reason: "Support"}),
        403,
        "forbidden"
      )
    end

    assert events("impersonation.started") == []
    assert Repo.aggregate(Impersonation, :count) == 0
  end

  test "impersonation validates reason and missing targets without creating sessions", %{auth: auth} do
    target = user_fixture()
    before_count = Repo.aggregate(Session, :count)

    for {reason, key} <- [
          {nil, "validation.required"},
          {"four", "validation.length_min"},
          {String.duplicate("a", 256), "validation.length_max"}
        ] do
      assert_field(
        post(auth, ~p"/api/v1/admin/users/#{target.id}/impersonation", %{reason: reason}),
        "reason",
        key
      )
    end

    assert_error(
      post(auth, ~p"/api/v1/admin/users/#{target.id}/impersonation", %{reason: []}),
      400,
      "bad_request"
    )

    assert_error(
      post(auth, ~p"/api/v1/admin/users/unknown/impersonation", %{reason: "Support"}),
      404,
      "not_found"
    )

    assert Repo.aggregate(Session, :count) == before_count
  end

  test "organizations search, paginate and expose member counts and users", %{auth: auth} do
    scope = scope_fixture(user_fixture(name: "Searchable company"))
    membership_fixture(scope, user_fixture())
    result = get(auth, ~p"/api/v1/admin/organizations?q=SEARCHABLE&perPage=1") |> json_response(200)
    assert [%{"id" => id, "members" => 2, "insertedAt" => inserted_at}] = result["data"]
    assert id == scope.organization.id
    assert inserted_at =~ ~r/Z$/
    assert result["meta"]["pagination"]["total"] == 1

    detail =
      get(auth, ~p"/api/v1/admin/organizations/#{id}") |> json_response(200) |> Map.fetch!("data")

    assert detail["organization"]["id"] == id
    assert length(detail["memberships"]) == 2
    assert Enum.all?(detail["memberships"], &is_binary(&1["user"]["email"]))
  end

  test "translations include CSV and table-only keys, search values, missing cells and pagination",
       %{auth: auth} do
    Repo.insert!(%Translation{
      key: "extra.table.key",
      locale: "en",
      value: "Search me",
      edited: true
    })

    page = get(auth, ~p"/api/v1/admin/translations?perPage=100") |> json_response(200)
    keys = Enum.map(page["data"], & &1["key"])
    assert keys == Enum.sort(keys)
    assert page["meta"]["pagination"]["total"] == length(I18n.Reference.rows()) + 1
    result = get(auth, ~p"/api/v1/admin/translations?q=SEARCH ME&missing=es") |> json_response(200)
    assert [%{"key" => "extra.table.key", "values" => values}] = result["data"]
    assert Enum.map(values, & &1["locale"]) == I18n.locales()
    assert List.last(values) == %{"locale" => "es", "value" => "", "edited" => false}

    assert json_response(get(auth, ~p"/api/v1/admin/translations?q=extra&missing=en"), 200)["data"] ==
             []
  end

  test "admin edits text → public catalogue new version → sync preserves edit", %{
    conn: conn,
    auth: auth,
    admin: admin
  } do
    I18n.sync()
    first = get(conn, ~p"/api/v1/locales/es")
    old_version = json_response(first, 200)["meta"]["version"]

    result =
      put(auth, ~p"/api/v1/admin/translations/nav.home", %{locale: "es", value: "Portada"})
      |> json_response(200)

    assert result["data"]["key"] == "nav.home"
    assert Enum.find(result["data"]["values"], &(&1["locale"] == "es"))["edited"]

    second =
      conn
      |> put_req_header("if-none-match", hd(get_resp_header(first, "etag")))
      |> get(~p"/api/v1/locales/es")

    assert json_response(second, 200)["data"]["nav.home"] == "Portada"
    assert json_response(second, 200)["meta"]["version"] != old_version
    I18n.sync()
    assert json_response(get(conn, ~p"/api/v1/locales/es"), 200)["data"]["nav.home"] == "Portada"
    [event] = events("translation.updated")
    assert event.actor_id == admin.id and event.metadata == %{"key" => "nav.home", "locale" => "es"}
    assert Repo.get_by!(Translation, key: "nav.home", locale: "es").edited
  end

  test "translation catalogue versions are deterministic across reloads", %{
    auth: auth,
    conn: conn
  } do
    previous = Application.get_env(:starter_kit, :i18n_inline_reload)
    Application.put_env(:starter_kit, :i18n_inline_reload, false)
    on_exit(fn -> Application.put_env(:starter_kit, :i18n_inline_reload, previous) end)
    Phoenix.PubSub.subscribe(StarterKit.PubSub, "i18n")

    assert json_response(
             put(auth, ~p"/api/v1/admin/translations/nav.home", %{locale: "es", value: "Portada"}),
             200
           )

    assert_receive {:reload, first_version}
    :sys.get_state(I18n.Catalog)
    assert json_response(get(conn, ~p"/api/v1/locales/es"), 200)["meta"]["version"] == first_version

    assert json_response(
             put(auth, ~p"/api/v1/admin/translations/nav.home", %{
               locale: "es",
               value: "New portada"
             }),
             200
           )

    assert_receive {:reload, second_version}
    :sys.get_state(I18n.Catalog)
    assert first_version != second_version
    I18n.Catalog.broadcast_reload()
    assert_receive {:reload, ^second_version}
    :sys.get_state(I18n.Catalog)

    assert json_response(get(conn, ~p"/api/v1/locales/es"), 200)["meta"]["version"] ==
             second_version
  end

  test "translation supports blank and URL-encoded new keys", %{auth: auth, conn: conn} do
    assert json_response(
             put(auth, "/api/v1/admin/translations/custom%3Akey", %{locale: "en", value: "Custom"}),
             200
           )["data"]["key"] == "custom:key"

    assert json_response(
             put(auth, ~p"/api/v1/admin/translations/nav.home", %{locale: "es", value: ""}),
             200
           )

    assert json_response(get(conn, ~p"/api/v1/locales/es"), 200)["data"]["nav.home"] == ""

    assert Enum.any?(
             json_response(get(auth, ~p"/api/v1/admin/translations?missing=es"), 200)["data"],
             &(&1["key"] == "nav.home")
           )
  end

  test "translation update validates locale, absent value, wrong type and length", %{auth: auth} do
    for {params, field, key} <- [
          {%{value: "text"}, "locale", "validation.required"},
          {%{locale: "xx", value: "text"}, "locale", "validation.inclusion"},
          {%{locale: "es"}, "value", "validation.required"},
          {%{locale: "es", value: String.duplicate("x", 20_001)}, "value", "validation.length_max"}
        ] do
      assert_field(put(auth, ~p"/api/v1/admin/translations/nav.home", params), field, key)
    end

    assert_error(
      put(auth, ~p"/api/v1/admin/translations/nav.home", %{locale: "es", value: []}),
      400,
      "bad_request"
    )

    assert events("translation.updated") == []
  end

  test "translation fill validates locale and reports missing AI configuration", %{auth: auth} do
    previous = Application.get_env(:starter_kit, StarterKit.AI)
    Application.put_env(:starter_kit, StarterKit.AI, [])
    on_exit(fn -> Application.put_env(:starter_kit, StarterKit.AI, previous) end)

    assert_field(
      post(auth, ~p"/api/v1/admin/translation-fills", %{}),
      "locale",
      "validation.required"
    )

    assert_field(
      post(auth, ~p"/api/v1/admin/translation-fills", %{locale: "en"}),
      "locale",
      "validation.inclusion"
    )

    assert_field(
      post(auth, ~p"/api/v1/admin/translation-fills", %{locale: "xx"}),
      "locale",
      "validation.inclusion"
    )

    assert_error(
      post(auth, ~p"/api/v1/admin/translation-fills", %{locale: "es"}),
      503,
      "ai_not_configured"
    )
  end

  test "synchronous translation fill returns 201 with the completed count and updates the catalogue",
       %{
         auth: auth,
         conn: conn
       } do
    Process.put(:ai_response, fn %{messages: [_, %{content: content}]} ->
      translated =
        content |> Jason.decode!() |> Map.new(fn {key, _} -> {key, "Translated text"} end)

      {:ok, %{"choices" => [%{"message" => %{"content" => Jason.encode!(translated)}}]}}
    end)

    assert json_response(
             put(auth, ~p"/api/v1/admin/translations/nav.home", %{locale: "es", value: ""}),
             200
           )

    before_version = json_response(get(conn, ~p"/api/v1/locales/es"), 200)["meta"]["version"]

    assert json_response(post(auth, ~p"/api/v1/admin/translation-fills", %{locale: "es"}), 201)[
             "data"
           ] == %{"count" => 1}

    after_fill = json_response(get(conn, ~p"/api/v1/locales/es"), 200)
    assert after_fill["meta"]["version"] != before_version
    assert after_fill["data"]["nav.home"] == "Translated text"
    assert Repo.get_by!(Translation, key: "nav.home", locale: "es").edited
    assert [%{metadata: %{"locale" => "es", "count" => 1}}] = events("translation.filled")
  end

  test "synchronous translation fill returns zero when no cells are missing", %{auth: auth} do
    Process.put(:ai_response, fn _ -> flunk("AI should not be called for a complete locale") end)

    assert json_response(post(auth, ~p"/api/v1/admin/translation-fills", %{locale: "es"}), 201)[
             "data"
           ] == %{"count" => 0}

    assert [%{metadata: %{"locale" => "es", "count" => 0}}] = events("translation.filled")
  end

  test "AI provider failure returns 503 without changing translation cells", %{
    auth: auth,
    conn: conn
  } do
    assert json_response(
             put(auth, ~p"/api/v1/admin/translations/nav.home", %{locale: "es", value: ""}),
             200
           )

    before_version = json_response(get(conn, ~p"/api/v1/locales/es"), 200)["meta"]["version"]
    Process.put(:ai_response, {:error, :timeout})

    assert_error(
      post(auth, ~p"/api/v1/admin/translation-fills", %{locale: "es"}),
      503,
      "ai_unavailable"
    )

    assert Repo.get_by!(Translation, key: "nav.home", locale: "es").value == ""

    assert json_response(get(conn, ~p"/api/v1/locales/es"), 200)["meta"]["version"] ==
             before_version

    assert events("translation.filled") == []
  end

  test "audit search by action or UUID resolves actor email and preserves metadata keys", %{
    auth: auth,
    admin: admin
  } do
    user = user_fixture()
    scope = Accounts.Scope.for_user(admin)

    {:ok, event} =
      Audit.record("custom.action",
        scope: scope,
        subject: user,
        metadata: %{"literal_key" => "value"}
      )

    for q <- ["CUSTOM.ACTION", user.id] do
      result = get(auth, ~p"/api/v1/admin/audit-events?q=#{q}&perPage=1") |> json_response(200)
      assert [%{"id" => id, "actorEmail" => email, "metadata" => metadata}] = result["data"]
      assert id == event.id and email == admin.email
      assert metadata == %{"literal_key" => "value"}
      assert result["meta"]["pagination"]["total"] == 1
    end
  end

  test "search treats SQL wildcards literally", %{auth: auth} do
    user = user_fixture(name: "Literal %_ name")
    scope = scope_fixture(user)
    {:ok, _} = Audit.record("literal.%_action", subject: user)
    assert [%{"id" => id}] = json_response(get(auth, ~p"/api/v1/admin/users?q=%_"), 200)["data"]
    assert id == user.id

    assert [%{"id" => id}] =
             json_response(get(auth, ~p"/api/v1/admin/organizations?q=%_"), 200)["data"]

    assert id == scope.organization.id

    assert [%{"action" => "literal.%_action"}] =
             json_response(get(auth, ~p"/api/v1/admin/audit-events?q=%_"), 200)["data"]
  end

  defp events(action), do: Repo.all(from e in Audit.AuditEvent, where: e.action == ^action)
  defp hidden_caller(conn, _admin, :anonymous), do: conn

  defp hidden_caller(conn, _admin, :user),
    do: bearer(conn, Accounts.generate_api_token(user_fixture()).token)

  defp hidden_caller(conn, admin, :impersonating),
    do:
      bearer(
        conn,
        Accounts.generate_api_token(user_fixture(), %{}, impersonator_user_id: admin.id).token
      )

  defp hidden_caller(conn, admin, :expired) do
    issued = Accounts.generate_api_token(admin)

    Repo.update!(
      Ecto.Changeset.change(issued.session, expires_at: DateTime.add(DateTime.utc_now(:second), -1))
    )

    bearer(conn, issued.token)
  end
end
