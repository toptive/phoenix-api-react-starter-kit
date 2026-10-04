defmodule StarterKitWeb.EmailOptOutTest do
  use StarterKitWeb.ConnCase, async: true
  import Ecto.Query
  import StarterKitWeb.ApiHelpers
  alias StarterKit.{Accounts, Notifications, Repo}
  alias StarterKit.Audit.AuditEvent

  setup %{conn: conn} do
    user = user_fixture()
    path = URI.parse(Notifications.unsubscribe_url(user.id, user.email)).path

    %{
      conn: api_conn(conn),
      user: user,
      path: path,
      preview: String.replace_suffix(path, "/opt-out", "")
    }
  end

  test "GET previews a subscription without changing it, with or without a bearer", ctx do
    for conn <- [ctx.conn, bearer(ctx.conn, Accounts.generate_api_token(ctx.user).token)] do
      assert json_response(get(conn, ctx.preview), 200)["data"] == %{
               "email" => ctx.user.email,
               "subscribed" => true
             }
    end

    assert Repo.reload!(ctx.user).optional_emails
  end

  test "JSON opt-out is idempotent, returns the subscription and audits once", ctx do
    for _ <- 1..2 do
      assert json_response(post(ctx.conn, ctx.path, %{}), 200)["data"] == %{
               "email" => ctx.user.email,
               "subscribed" => false
             }
    end

    refute Repo.reload!(ctx.user).optional_emails

    assert Repo.aggregate(
             from(a in AuditEvent, where: a.action == "user.optional_emails_stopped"),
             :count
           ) == 1

    assert json_response(get(ctx.conn, ctx.preview), 200)["data"]["subscribed"] == false
  end

  test "RFC 8058 form POST works without cookies or CSRF and returns a bare 200", ctx do
    conn = put_req_header(ctx.conn, "content-type", "application/x-www-form-urlencoded")

    for _ <- 1..2 do
      response = post(conn, ctx.path, "List-Unsubscribe=One-Click")
      assert response(response, 200) == ""
      assert get_resp_header(response, "set-cookie") == []
    end

    refute Repo.reload!(ctx.user).optional_emails
  end

  test "bad tokens and changed-address tokens are 404", ctx do
    assert_error(get(ctx.conn, "/api/v1/email-subscriptions/bad"), 404, "not_found")
    assert_error(post(ctx.conn, "/api/v1/email-subscriptions/bad/opt-out", %{}), 404, "not_found")
    ctx.user |> Ecto.Changeset.change(email: unique_email()) |> Repo.update!()
    assert_error(get(ctx.conn, ctx.preview), 404, "not_found")
    assert_error(post(ctx.conn, ctx.path, %{}), 404, "not_found")
  end

  test "optional mail sends an API unsubscribe header and a SPA footer link", ctx do
    {:ok, _} =
      Notifications.notify(ctx.user, :product_update, %{url: "https://app.example.com/news"})

    assert_receive {:email, email}
    assert email.headers["List-Unsubscribe"] =~ "http://localhost:4000/api/v1/email-subscriptions/"
    assert email.headers["List-Unsubscribe-Post"] == "List-Unsubscribe=One-Click"
    assert email.text_body =~ "http://localhost:5173/email-subscriptions/"
    assert email.text_body =~ "http://localhost:5173/settings/email-preferences/edit"
  end

  test "opt-out is limited to 120 per minute", ctx do
    for _ <- 1..120, do: post(ctx.conn, ctx.path, %{})
    assert_error(post(ctx.conn, ctx.path, %{}), 429, "rate_limited")
  end
end
