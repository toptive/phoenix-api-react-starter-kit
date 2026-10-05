defmodule StarterKit.EmailLayoutTest do
  use ExUnit.Case, async: true

  alias StarterKit.I18n
  alias StarterKit.Notifications
  alias StarterKit.Notifications.Email

  @brand Application.compile_env!(:starter_kit, :mail_brand)
  @site Application.compile_env!(:starter_kit, :public_url)

  # Every binding any kind uses, so no placeholder is left unfilled.
  @data %{
    "url" => "https://app.example.com/action",
    "inviter" => "Ana",
    "organization" => "Acme",
    "plan" => "Pro",
    "date" => "2026-11-01",
    "amount" => "USD 190.00",
    "title" => "Shared folders",
    "summary" => "Share a folder with your team.",
    "unsubscribe_url" => "https://app.example.com/email-subscriptions/t/opt-out"
  }

  defp build(kind, locale, data \\ @data, group \\ nil) do
    recipient = %{"email" => "bo@example.com", "name" => "Bo", "locale" => locale}
    Email.build(recipient, kind, data, group || Notifications.group(kind))
  end

  test "every kind renders the branded layout in every locale" do
    for kind <- Notifications.kinds(), locale <- I18n.locales() do
      email = build(kind, locale)
      html = email.html_body
      where = "#{kind}/#{locale}"

      assert html =~ ~s(src="#{@site}/images/mail/logo.png"), "#{where}: logo header"
      assert html =~ ~s(alt="#{@brand.app_name}"), "#{where}: logo alt"
      assert html =~ "<strong>#{@brand.app_name}</strong>", "#{where}: footer brand"
      assert html =~ ~r/<h1[^>]*>[^<]+<\/h1>/, "#{where}: headline"
      assert length(Regex.scan(~r/bgcolor="#{@brand.accent}"/, html)) == 1, "#{where}: one button"
      assert html =~ ~s(lang="#{locale}"), where

      for body <- [email.subject, email.text_body, visible_text(html)] do
        refute body =~ ~r/\bmail\.[a-z_]+\.[a-z_0-9]+/, "#{where}: a missing catalogue key"
        refute body =~ "{{", "#{where}: an unfilled placeholder"
      end
    end
  end

  test "the dev gallery preview fills every kind in every locale" do
    for kind <- Notifications.kinds(), locale <- I18n.locales() do
      email = Notifications.preview(kind, locale)

      for body <- [email.subject, email.text_body, visible_text(email.html_body)] do
        refute body =~ "{{",
               "#{kind}/#{locale}: add the binding to @preview_data in notifications.ex"
      end

      if Notifications.group(kind) == :optional do
        assert email.headers["List-Unsubscribe"], "#{kind}/#{locale}: unsubscribe header"
      end
    end
  end

  test "the footer says why the email came; only optional mail offers unsubscribe" do
    links = %{
      "unsubscribe_url" => "https://u.example.com/x",
      "preferences_url" => "https://u.example.com/p"
    }

    access = build("magic_link", "en", Map.merge(@data, links))
    refute access.html_body =~ "https://u.example.com/x"
    refute Map.has_key?(access.headers, "List-Unsubscribe")
    assert access.provider_options.message_stream == "outbound"
    reason = I18n.t("mail.footer", %{"app" => @brand.app_name}, "en")
    assert access.html_body =~ reason |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

    optional = build("invitation", "en", Map.merge(@data, links), :optional)
    assert optional.html_body =~ ~s(href="https://u.example.com/x")
    assert optional.html_body =~ ~s(href="https://u.example.com/p")
    assert optional.headers["List-Unsubscribe"] == "<https://u.example.com/x>"
    assert optional.provider_options.message_stream == "broadcast"
  end

  test "Postmark never tracks opens or links" do
    for kind <- Notifications.kinds() do
      assert %{track_opens: false, track_links: "None"} = build(kind, "en").provider_options
    end
  end

  test "a test-mode email carries the badge above the headline, never in the body text" do
    html = build("renewal_notice", "en", Map.put(@data, "test", true)).html_body
    [before_headline, _] = String.split(html, "<h1", parts: 2)

    assert before_headline =~ "Test mode"
    refute build("renewal_notice", "en").html_body =~ "Test mode"
  end

  test "values are escaped" do
    html = build("invitation", "en", Map.put(@data, "organization", "<b>Acme</b>")).html_body
    assert html =~ "&lt;b&gt;Acme&lt;/b&gt;"
    refute html =~ "<b>Acme"
  end

  test "only the shared layout builds mail" do
    others =
      Path.wildcard("lib/**/*.ex")
      |> Enum.reject(&(&1 == "lib/starter_kit/notifications/email.ex"))
      |> Enum.filter(
        &(File.read!(&1) =~ ~r/html_body\(|text_body\(|import Swoosh\.Email|Swoosh\.Email\.new/)
      )

    assert others == [], "send mail through StarterKit.Notifications.notify/3 (the branded layout)"
  end

  defp visible_text(html) do
    html
    |> String.replace(~r/<(style|head)\b.*?<\/\1>/s, "")
    |> String.replace(~r/<[^>]*>/, " ")
  end
end
