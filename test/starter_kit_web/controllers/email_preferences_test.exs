defmodule StarterKitWeb.EmailPreferencesTest do
  use StarterKitWeb.ConnCase, async: true

  alias StarterKit.{I18n, Notifications, Repo}
  alias StarterKitWeb.Dev.EmailPreviewController

  describe "settings: email preferences" do
    setup :register_and_log_in_user

    test "shows the preference and turns optional mail back on", %{conn: conn, user: user} do
      Repo.update!(Ecto.Changeset.change(user, optional_emails: false))

      page = get(conn, ~p"/settings/email-preferences/edit")
      assert inertia_component(page) == "settings/email-preferences/edit"
      assert inertia_props(page).optionalEmails == false

      conn = patch(conn, ~p"/settings/email-preferences", %{"user" => %{"optionalEmails" => true}})
      assert redirected_to(conn) == ~p"/settings/email-preferences/edit"
      assert Repo.reload!(user).optional_emails
    end
  end

  test "settings: email preferences need a sign-in", %{conn: conn} do
    assert conn |> get(~p"/settings/email-preferences/edit") |> redirected_to() =~ "/session"
  end

  describe "dev gallery (/dev/emails, dev only)" do
    defp call(action, params) do
      build_conn(:get, "/dev/emails", params)
      |> Plug.Conn.fetch_query_params()
      |> Phoenix.Controller.put_format("html")
      |> EmailPreviewController.call(action)
    end

    test "lists every kind with a link per locale" do
      html = call(:index, %{}) |> html_response(200)

      for kind <- Notifications.kinds(), locale <- I18n.locales() do
        assert html =~ ~s(href="/dev/emails/#{kind}?locale=#{locale}")
      end
    end

    test "shows one kind in one locale: headers, HTML in an iframe, text part" do
      html = call(:show, %{"kind" => "product_update", "locale" => "es"}) |> html_response(200)
      email = Notifications.preview("product_update", "es")

      assert html =~ "List-Unsubscribe"
      assert html =~ "broadcast"
      assert html =~ ~s(<iframe title="Email at phone width" width="375" srcdoc=")
      assert html =~ Phoenix.HTML.html_escape(email.subject) |> Phoenix.HTML.safe_to_string()
      refute html =~ email.html_body, "the email HTML is escaped into srcdoc"
    end

    test "an unknown kind is a 404" do
      assert call(:show, %{"kind" => "nope"}) |> response(404)
    end
  end

  test "the gallery route is off without dev_routes (test, prod)" do
    assert Phoenix.Router.route_info(StarterKitWeb.Router, "GET", "/dev/emails", "localhost") ==
             :error
  end
end
