defmodule StarterKit.Notifications.Email do
  @moduledoc false
  # Builds the Swoosh email for a notification. ONE branded layout for every kind, as
  # structure and not prose: logo header → headline → one short lead → a facts block
  # (label/value rows) → ONE primary button → at most two short muted notes → footer with
  # the reason for the email (+ preferences / unsubscribe links when the kind has them).
  # Table-based, inline styles, 600 px, readable at 375 px, dark-mode safe.
  # Called only by StarterKit.Notifications; email_layout_test.exs fails if any other
  # module builds mail.
  #
  # Copy per kind (i18n): mail.<kind>.subject, .headline, .lead, .action, and optional
  # .note1, .note2, .footer (falls back to mail.footer). Facts labels: mail.fact.<label>.

  import Swoosh.Email

  alias StarterKit.I18n

  @brand Map.merge(
           %{
             app_name: "StarterKit",
             accent: "#11694F",
             text: "#16222B",
             muted: "#5B6770",
             paper: "#F6F8F6",
             rule: "#D9E0DC",
             highlight: "#F3DA5A"
           },
           Application.compile_env(:starter_kit, :mail_brand, %{})
         )

  # Facts per kind: `{label, source}`. A source is `{:bind, key}` (from the mail data) or
  # `{:t, key}` (a catalogue text). Rows with an empty value are dropped.
  @facts %{
    "magic_link" => [{"account", {:bind, "email"}}, {"valid_for", {:t, "mail.value.minutes_15"}}],
    "email_change" => [{"new_email", {:bind, "email"}}],
    "invitation" => [
      {"invited_by", {:bind, "inviter"}},
      {"organization", {:bind, "organization"}},
      {"expires", {:t, "mail.value.days_7"}}
    ],
    "renewal_notice" => [
      {"plan", {:bind, "plan"}},
      {"renews_on", {:bind, "date"}},
      {"amount", {:bind, "amount"}}
    ]
  }

  # sobelow_skip ["XSS.HTML"]
  # Every interpolated value goes through escape/1 (Phoenix.HTML.html_escape); this is an
  # email body, not a browser response.
  def build(%{"email" => to, "name" => name, "locale" => locale}, kind, data, group) do
    bindings = Map.merge(%{"name" => name, "email" => to, "app" => @brand.app_name}, data)
    t = fn key -> I18n.t("mail.#{kind}.#{key}", bindings, locale) end
    subject = t.("subject")

    m = %{
      locale: locale,
      subject: subject,
      badge: data["test"] == true && I18n.t("mail.badge.test", %{}, locale),
      headline: optional(t.("headline")) || subject,
      lead: optional(t.("lead")),
      facts: facts(kind, bindings, locale),
      action: t.("action"),
      url: data["url"],
      notes: Enum.reject([optional(t.("note1")), optional(t.("note2"))], &is_nil/1),
      footer: optional(t.("footer")) || I18n.t("mail.footer", bindings, locale),
      links: if(group == :optional, do: footer_links(data, locale), else: []),
      site: Application.get_env(:starter_kit, :public_url, "http://localhost:4000")
    }

    new()
    |> to({name, to})
    |> from(StarterKit.Mailer.from(locale))
    |> subject(subject)
    |> text_body(text(m))
    |> html_body(html(m))
    |> delivery_options(group, data)
  end

  # Postmark: no open or link tracking (no pixels, no rewritten links). Optional mail goes
  # through the broadcast stream with a List-Unsubscribe header; everything else through
  # the transactional stream. Other adapters ignore provider options.
  defp delivery_options(email, group, data) do
    streams = Application.get_env(:starter_kit, :postmark_streams, %{})

    email =
      email
      |> put_provider_option(:track_opens, false)
      |> put_provider_option(:track_links, "None")

    if group == :optional do
      email
      |> put_provider_option(:message_stream, streams[:broadcast] || "broadcast")
      |> unsubscribe_headers(data["unsubscribe_url"])
    else
      put_provider_option(email, :message_stream, streams[:transactional] || "outbound")
    end
  end

  # RFC 8058: mail clients show an "Unsubscribe" button and POST
  # `List-Unsubscribe=One-Click` to the URL (no login, no cookies). One-click needs HTTPS;
  # a plain-http URL (dev) keeps only List-Unsubscribe.
  defp unsubscribe_headers(email, url) do
    email = header(email, "List-Unsubscribe", "<#{url}>")

    if String.starts_with?(url, "https://"),
      do: header(email, "List-Unsubscribe-Post", "List-Unsubscribe=One-Click"),
      else: email
  end

  # A missing catalogue key comes back as the key itself.
  defp optional("mail." <> _), do: nil
  defp optional(text), do: text

  defp facts(kind, bindings, locale) do
    for {label, source} <- Map.get(@facts, kind, []),
        value = fact_value(source, bindings, locale),
        value not in [nil, ""] do
      {I18n.t("mail.fact.#{label}", %{}, locale), to_string(value)}
    end
  end

  defp fact_value({:bind, key}, bindings, _), do: bindings[key]
  defp fact_value({:t, key}, bindings, locale), do: I18n.t(key, bindings, locale)

  # Only optional mail (lifecycle, marketing) shows these: access and transactional mail
  # (sign-in links, invitations, renewals) never offers an unsubscribe.
  defp footer_links(data, locale) do
    [
      data["preferences_url"] && {I18n.t("mail.preferences", %{}, locale), data["preferences_url"]},
      data["unsubscribe_url"] && {I18n.t("mail.unsubscribe", %{}, locale), data["unsubscribe_url"]}
    ]
    |> Enum.filter(& &1)
  end

  # -- plain text -------------------------------------------------------------------------

  defp text(m) do
    [
      m.badge && "[#{m.badge}]",
      m.headline,
      m.lead,
      m.facts != [] && Enum.map_join(m.facts, "\n", fn {label, value} -> "#{label}: #{value}" end),
      m.url && "#{m.action}: #{m.url}",
      m.notes != [] && Enum.join(m.notes, "\n"),
      Enum.join([m.footer | Enum.map(m.links, fn {label, url} -> "#{label}: #{url}" end)], "\n"),
      "#{@brand.app_name} — #{m.site}"
    ]
    |> Enum.reject(&(&1 in [nil, false, ""]))
    |> Enum.join("\n\n")
  end

  # -- html -------------------------------------------------------------------------------

  @font "-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif"

  defp html(m) do
    b = @brand

    """
    <!doctype html>
    <html lang="#{escape(m.locale)}"><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <meta name="color-scheme" content="light dark"><meta name="supported-color-schemes" content="light dark">
    <title>#{escape(m.subject)}</title>
    <style>
    @media (max-width:620px){.pad{padding-left:20px!important;padding-right:20px!important}.h1{font-size:23px!important}}
    @media (prefers-color-scheme:dark){
    .bg-page{background:#121C24!important}.bg-card{background:#1B2731!important;border-color:#2C3A45!important}
    .t-ink{color:#EEF2EF!important}.t-muted{color:#A7B3BA!important}.t-link{color:#7FD1B0!important}
    .rule{border-color:#2C3A45!important}
    }
    </style></head>
    <body class="bg-page" style="margin:0;padding:0;background:#{b.paper};-webkit-text-size-adjust:100%">
    <div style="display:none;max-height:0;overflow:hidden">#{escape(m.lead || m.headline)}</div>
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" class="bg-page" bgcolor="#{b.paper}" style="background:#{b.paper}"><tr><td align="center" style="padding:24px 12px 40px">
    <table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" style="width:100%;max-width:600px">
    <tr><td class="pad" style="padding:0 32px 20px">
    <a href="#{escape(m.site)}" class="t-ink" style="text-decoration:none;color:#{b.text};font-family:#{@font};font-size:18px;font-weight:700"><img src="#{escape(m.site <> "/images/mail/logo.png")}" width="32" height="32" alt="#{escape(b.app_name)}" style="display:inline-block;vertical-align:middle;border:0;width:32px;height:32px;margin-right:10px"><span style="vertical-align:middle">#{escape(b.app_name)}</span></a>
    </td></tr>
    <tr><td class="pad bg-card" bgcolor="#FFFFFF" style="background:#FFFFFF;border:1px solid #{b.rule};border-radius:12px;padding:32px;font-family:#{@font};color:#{b.text};font-size:16px;line-height:1.55">
    #{badge(m.badge)}<h1 class="h1 t-ink" style="margin:0;font-size:26px;line-height:1.25;font-weight:700;color:#{b.text}">#{escape(m.headline)}</h1>
    <div style="margin:10px 0 20px;width:56px;height:6px;border-radius:3px;background:#{b.highlight};font-size:0;line-height:0">&nbsp;</div>
    #{lead(m.lead)}#{facts_html(m.facts)}#{button(m)}#{notes_html(m.notes)}
    </td></tr>
    <tr><td class="pad t-muted" style="padding:24px 32px 0;font-family:#{@font};font-size:13px;line-height:1.55;color:#{b.muted}">
    <p class="t-muted" style="margin:0 0 10px;color:#{b.muted}">#{escape(m.footer)}</p>
    #{footer_links_html(m.links)}<p class="t-muted" style="margin:0;color:#{b.muted}"><strong>#{escape(b.app_name)}</strong><br><a class="t-muted" href="#{escape(m.site)}" style="color:#{b.muted}">#{escape(host(m.site))}</a></p>
    </td></tr>
    </table></td></tr></table>
    </body></html>
    """
  end

  defp badge(false), do: ""

  defp badge(text),
    do:
      ~s(<p style="margin:0 0 14px"><span style="display:inline-block;background:#{@brand.highlight};color:#3D3300;font-size:13px;font-weight:700;padding:3px 10px;border-radius:999px">#{escape(text)}</span></p>)

  defp lead(nil), do: ""

  defp lead(text),
    do: ~s(<p class="t-ink" style="margin:0 0 20px;color:#{@brand.text}">#{escape(text)}</p>)

  defp facts_html([]), do: ""

  defp facts_html(facts) do
    rows =
      Enum.map_join(facts, fn {label, value} ->
        ~s(<tr><td class="t-muted rule" valign="top" style="padding:11px 12px 11px 0;border-top:1px solid #{@brand.rule};font-size:14px;color:#{@brand.muted};width:38%">#{escape(label)}</td><td class="t-ink rule" valign="top" style="padding:11px 0;border-top:1px solid #{@brand.rule};font-size:15px;font-weight:600;color:#{@brand.text};word-break:break-word">#{escape(value)}</td></tr>)
      end)

    ~s(<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" class="rule" style="margin:0 0 4px;border-bottom:1px solid #{@brand.rule}">#{rows}</table>)
  end

  defp button(%{url: nil}), do: ""

  defp button(m) do
    ~s(<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:24px 0 8px"><tr><td align="center" bgcolor="#{@brand.accent}" style="background:#{@brand.accent};border-radius:10px"><a href="#{escape(m.url)}" style="display:inline-block;padding:14px 26px;color:#FFFFFF;font-weight:700;font-size:16px;line-height:1.2;text-decoration:none;font-family:#{@font}">#{escape(m.action)}</a></td></tr></table>)
  end

  defp notes_html([]), do: ""

  defp notes_html(notes) do
    Enum.map_join(notes, fn note ->
      ~s(<p class="t-muted" style="margin:16px 0 0;font-size:14px;color:#{@brand.muted}">#{escape(note)}</p>)
    end)
  end

  defp footer_links_html([]), do: ""

  defp footer_links_html(links) do
    anchors =
      Enum.map_join(links, "&nbsp;&nbsp;&nbsp;", fn {label, url} ->
        ~s(<a class="t-link" href="#{escape(url)}" style="color:#{@brand.accent};text-decoration:underline">#{escape(label)}</a>)
      end)

    ~s(<p style="margin:0 0 10px">#{anchors}</p>)
  end

  defp host(url), do: URI.parse(url).host || url

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
