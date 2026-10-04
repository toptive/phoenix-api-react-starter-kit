defmodule StarterKitWeb.ApiJobsTest do
  use StarterKitWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import StarterKitWeb.ApiHelpers
  alias StarterKit.{Accounts, Repo}
  alias StarterKitWeb.{Endpoint, JobsAccess}

  setup %{conn: conn} do
    conn = api_conn(conn)
    admin = superadmin_fixture()
    issued = Accounts.generate_api_token(admin)
    %{conn: conn, admin: admin, issued: issued, auth: bearer(conn, issued.token)}
  end

  test "jobs access mints a scoped short-lived signed HttpOnly cookie and mounts Oban", %{
    conn: conn,
    auth: auth
  } do
    start_dashboard_support()
    granted = post(auth, ~p"/api/v1/admin/jobs-access", %{})
    url = json_response(granted, 201)["data"]["url"]
    assert url =~ Application.fetch_env!(:starter_kit, :api_origin) <> "/admin/jobs/session?ticket="
    assert granted.resp_cookies == %{}
    exchanged = get(conn |> put_req_header("accept", "text/html"), url)
    assert redirected_to(exchanged) == "/admin/jobs"
    cookie = exchanged.resp_cookies["_starter_kit_jobs"]
    assert get(conn |> put_req_header("accept", "text/html"), url).status == 404
    assert Repo.get_by!(StarterKit.Audit.AuditEvent, action: "admin.jobs_dashboard_opened")
    assert cookie.max_age == 300 and cookie.http_only and cookie.same_site == "Strict"
    assert cookie.path == "/admin/jobs"
    refute cookie.value =~ "Bearer"
    browser = browser_cookie(conn, cookie.value)
    result = get(browser, ~p"/admin/jobs")
    assert html_response(result, 200) =~ "Oban"
    assert get_resp_header(result, "content-security-policy") |> hd() =~ "nonce-"
  end

  test "jobs route and assets hide from every caller without a grant", %{conn: conn, auth: auth} do
    for caller <- [
          conn,
          auth,
          log_in_user(conn, superadmin_fixture()),
          log_in_user(conn, user_fixture())
        ],
        path <- ["/admin/jobs", "/admin/jobs/jobs", "/admin/jobs/css-invalid"] do
      assert get(caller |> put_req_header("accept", "text/html"), path).status == 404
    end
  end

  test "forged, expired, ordinary and impersonating grants cannot access jobs", %{
    conn: conn,
    issued: issued,
    admin: admin
  } do
    ordinary = Accounts.generate_api_token(user_fixture())
    impersonation = Accounts.generate_api_token(user_fixture(), %{}, impersonator_user_id: admin.id)

    grants = [
      "forged",
      Phoenix.Token.sign(Endpoint, "jobs-access", issued.session.id,
        signed_at: System.system_time(:second) - 301
      ),
      Phoenix.Token.sign(Endpoint, "jobs-access", ordinary.session.id),
      Phoenix.Token.sign(Endpoint, "jobs-access", impersonation.session.id)
    ]

    for grant <- grants do
      assert get(browser_cookie(conn, grant), ~p"/admin/jobs").status == 404
    end
  end

  test "revoking bearer invalidates an already minted grant", %{
    conn: conn,
    auth: auth,
    issued: issued
  } do
    granted = post(auth, ~p"/api/v1/admin/jobs-access", %{})
    token = exchange_token(conn, granted)
    assert response(delete(auth, ~p"/api/v1/auth/session"), 204) == ""
    assert get(browser_cookie(conn, token), ~p"/admin/jobs").status == 404
    assert JobsAccess.resolve_access(token) == {:forbidden, "/session/new"}
    assert Repo.reload!(issued.session).revoked_at
  end

  test "demoting superadmin invalidates a grant on both HTTP and socket reconnect", %{
    conn: conn,
    auth: auth,
    admin: admin
  } do
    granted = post(auth, ~p"/api/v1/admin/jobs-access", %{})
    token = exchange_token(conn, granted)
    assert json_response(put(auth, ~p"/api/v1/admin/users/#{admin.id}", %{role: "user"}), 200)
    assert get(browser_cookie(conn, token), ~p"/admin/jobs").status == 404
    assert JobsAccess.resolve_access(token) == {:forbidden, "/session/new"}
  end

  test "connected jobs socket loses permission after admin logout", %{conn: conn, auth: auth} do
    start_dashboard_support()
    granted = post(auth, ~p"/api/v1/admin/jobs-access", %{})
    token = exchange_token(conn, granted)
    {:ok, view, _html} = live(browser_cookie(conn, token), ~p"/admin/jobs")
    assert response(delete(auth, ~p"/api/v1/auth/session"), 204) == ""
    send(view.pid, :jobs_access_check)
    assert_redirect(view, "/session/new")
  end

  test "handoff refuses missing, forged, expired and revoked tickets", %{
    conn: conn,
    auth: auth,
    issued: issued
  } do
    assert get(conn, ~p"/api/v1/bootstrap")
           |> json_response(200)
           |> get_in(["data", "app", "jobsDashboard"])

    browser = conn |> put_req_header("accept", "text/html")
    assert get(browser, "/admin/jobs/session").status == 404
    assert get(browser, "/admin/jobs/session?ticket=forged").status == 404
    url = json_response(post(auth, ~p"/api/v1/admin/jobs-access", %{}), 201)["data"]["url"]
    ticket = URI.decode_query(URI.parse(url).query)["ticket"]
    {:ok, payload} = Phoenix.Token.verify(Endpoint, "jobs-ticket", ticket, max_age: 60)

    expired =
      Phoenix.Token.sign(Endpoint, "jobs-ticket", payload,
        signed_at: System.system_time(:second) - 61
      )

    assert get(browser, "/admin/jobs/session?" <> URI.encode_query(%{ticket: expired})).status ==
             404

    Repo.update!(Ecto.Changeset.change(issued.session, revoked_at: DateTime.utc_now(:second)))
    assert get(browser, url).status == 404
  end

  test "jobs handoff uses the API origin and cleanup purges unused expired tickets", %{auth: auth} do
    previous = Application.fetch_env!(:starter_kit, :api_origin)
    Application.put_env(:starter_kit, :api_origin, "https://api.example.test")
    on_exit(fn -> Application.put_env(:starter_kit, :api_origin, previous) end)

    url = json_response(post(auth, ~p"/api/v1/admin/jobs-access", %{}), 201)["data"]["url"]
    assert url =~ "https://api.example.test/admin/jobs/session?ticket="
    ticket = Repo.get_by!(Accounts.UserToken, context: "jobs_access")
    assert :ok = Accounts.purge_expired_tokens()
    assert Repo.get(Accounts.UserToken, ticket.id)

    Repo.update!(
      Ecto.Changeset.change(ticket, inserted_at: DateTime.add(DateTime.utc_now(:second), -61))
    )

    assert :ok = Accounts.purge_expired_tokens()
    refute Repo.get(Accounts.UserToken, ticket.id)
  end

  defp exchange_token(conn, granted) do
    url = json_response(granted, 201)["data"]["url"]
    get(conn |> put_req_header("accept", "text/html"), url).resp_cookies["_starter_kit_jobs"].value
  end

  defp start_dashboard_support do
    conf = %{Oban.config() | testing: :disabled}
    start_supervised!({Oban.Sonar, conf: conf, name: Oban.Registry.via(Oban, Oban.Sonar)})
    start_supervised!({Oban.Met, conf: conf, reporter: [auto_migrate: false]})
  end

  defp browser_cookie(conn, token) do
    conn
    |> delete_req_header("content-type")
    |> put_req_header("accept", "text/html")
    |> put_req_cookie("_starter_kit_jobs", token)
  end
end
