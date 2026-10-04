defmodule StarterKitWeb.Plugs.PageViewsTest do
  use StarterKitWeb.ConnCase, async: true

  alias StarterKitWeb.Plugs.PageViews

  @agent "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) Safari/604.1"

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "user-agent", @agent)}
  end

  test "a public page view carries page type, locale and utm, and no person", %{conn: conn} do
    conn
    |> put_req_header("referer", "https://www.google.com/search?q=secret")
    |> get("/es?utm_source=newsletter&utm_medium=email&utm_campaign=launch&email=a@b.co")

    assert_received {:analytics, %{event: "public_page_viewed", distinct_id: id, properties: props}}

    assert {:ok, _} = Ecto.UUID.cast(id)

    assert props == %{
             "page_type" => "home.show",
             "locale" => "es",
             "path" => "/es",
             "referrer_domain" => "google.com",
             "utm_source" => "newsletter",
             "utm_medium" => "email",
             "utm_campaign" => "launch",
             "$process_person_profile" => false
           }
  end

  test "a signed-in visitor is still anonymous", %{conn: conn} do
    conn |> log_in_user(StarterKit.Fixtures.user_fixture()) |> get("/")

    assert_received {:analytics, %{event: "public_page_viewed", distinct_id: id, properties: props}}
    assert {:ok, _} = Ecto.UUID.cast(id)
    assert props["$process_person_profile"] == false
  end

  test "an own-site referrer is not reported", %{conn: conn} do
    conn |> put_req_header("referer", "http://www.example.com/legal/terms") |> get("/")

    assert_received {:analytics, %{event: "public_page_viewed", properties: props}}
    assert props["referrer_domain"] == nil
  end

  test "crawlers, missing agents, prefetches and partial reloads are skipped", %{conn: conn} do
    get(put_req_header(conn, "user-agent", "Mozilla/5.0 (compatible; Googlebot/2.1)"), "/")
    get(delete_req_header(conn, "user-agent"), "/")
    get(put_req_header(conn, "sec-purpose", "prefetch"), "/")

    conn
    |> put_req_header("x-inertia", "true")
    |> put_req_header("x-inertia-partial-data", "legal")
    |> get("/")

    refute_received {:analytics, %{event: "public_page_viewed"}}
  end

  test "non-public pages and errors are not tracked", %{conn: conn} do
    get(conn, "/registration/new")
    get(conn, "/legal/does-not-exist")
    refute_received {:analytics, %{event: "public_page_viewed"}}
  end

  test "the plug adds no cookie and no header" do
    conn =
      :get
      |> Plug.Test.conn("/")
      |> put_req_header("user-agent", @agent)
      |> PageViews.call([])
      |> put_resp_content_type("text/html")
      |> send_resp(200, "ok")

    assert conn.resp_cookies == %{}
    assert get_resp_header(conn, "set-cookie") == []
    assert get_resp_header(conn, "cache-control") == ["max-age=0, private, must-revalidate"]
    assert_received {:analytics, %{event: "public_page_viewed"}}
  end
end
