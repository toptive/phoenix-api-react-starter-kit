defmodule StarterKitWeb.EmailOptOutTest do
  use StarterKitWeb.ConnCase, async: true

  alias StarterKit.{Notifications, Repo}

  setup do
    user = user_fixture()
    url = Notifications.unsubscribe_url(user.id, user.email)
    %{user: user, path: URI.parse(url).path}
  end

  test "the footer link shows a page with one button and changes nothing", %{conn: conn} = ctx do
    conn = get(conn, ctx.path)
    assert inertia_component(conn) == "email-opt-out/show"
    assert %{email: email, subscribed: true} = inertia_props(conn)
    assert email == ctx.user.email
    assert Repo.reload!(ctx.user).optional_emails
  end

  test "RFC 8058 one-click POST works with no session or CSRF token, twice", %{conn: conn} = ctx do
    for _ <- 1..2 do
      conn = post(conn, ctx.path, %{"List-Unsubscribe" => "One-Click"})
      assert response(conn, 200) == ""
    end

    refute Repo.reload!(ctx.user).optional_emails

    # Tests skip CSRF checks, so prove the route has none: no session, no forgery check.
    assert %{pipe_through: [:one_click]} =
             Phoenix.Router.route_info(StarterKitWeb.Router, "POST", ctx.path, "localhost")
  end

  test "the page button unsubscribes and the page then says so", %{conn: conn} = ctx do
    conn = conn |> inertia() |> post(ctx.path, %{})
    assert redirected_to(conn, 303) == ctx.path

    conn = get(build_conn(), ctx.path)
    assert %{subscribed: false} = inertia_props(conn)
  end

  test "a token that names nobody: 404 on POST, home with a message on GET", %{conn: conn} = ctx do
    bad = ctx.path |> String.replace("/opt-out", "x/opt-out")

    assert conn |> post(bad, %{"List-Unsubscribe" => "One-Click"}) |> response(404)
    assert Repo.reload!(ctx.user).optional_emails

    conn = get(conn, bad)
    assert redirected_to(conn) == "/"
    assert Phoenix.Flash.get(conn.assigns.flash, :error)
  end
end
