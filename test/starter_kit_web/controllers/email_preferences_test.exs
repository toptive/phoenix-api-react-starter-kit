defmodule StarterKitWeb.EmailPreferencesTest do
  use StarterKitWeb.ConnCase, async: true

  alias StarterKit.{I18n, Notifications}
  alias StarterKitWeb.Dev.EmailPreviewController

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

  test "the gallery route is off without dev_routes (test, prod)", %{conn: conn} do
    assert get(conn, "/dev/emails").status == 404
  end
end
