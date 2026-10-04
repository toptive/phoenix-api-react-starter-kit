defmodule StarterKitWeb.Dev.EmailPreviewHTML do
  @moduledoc false
  # Standalone pages for `/dev/emails` (no React, no app layout). The email HTML goes
  # into an iframe `srcdoc` (escaped as an attribute), so its styles stay inside it.

  use StarterKitWeb, :html

  @style """
  body{margin:0;font-family:system-ui,sans-serif;background:Canvas;color:CanvasText}
  main{max-width:1200px;margin:0 auto;padding:24px}
  h1{font-size:22px;margin:0 0 4px} p{margin:4px 0}
  table{border-collapse:collapse;width:100%;margin:16px 0}
  th,td{text-align:left;padding:10px 8px;border-bottom:1px solid GrayText;vertical-align:top}
  a{color:LinkText} .muted{color:GrayText} .tag{font-size:12px;border:1px solid GrayText;border-radius:999px;padding:1px 8px}
  .frames{display:flex;gap:24px;flex-wrap:wrap;align-items:flex-start}
  .frames figure{margin:0} .frames figcaption{font-size:13px;margin-bottom:6px}
  iframe{border:1px solid GrayText;border-radius:8px;background:#fff;height:900px}
  pre{white-space:pre-wrap;border:1px solid GrayText;border-radius:8px;padding:16px;max-width:680px}
  """

  def index(assigns) do
    assigns = Map.put(assigns, :style, @style)

    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="robots" content="noindex" />
        <title>Emails · dev</title>
        <style>
          {@style}
        </style>
      </head>
      <body>
        <main>
          <h1>Emails</h1>
          <p class="muted">
            Every notification kind, rendered with sample data. Nothing is sent. Copy lives in
            <code>i18n/translations.csv</code>
            (<code>mail.&lt;kind&gt;.*</code>).
          </p>
          <table>
            <thead>
              <tr>
                <th>Kind</th>
                <th>Group</th>
                <th>Subject (en)</th>
                <th>Preview</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={row <- @rows}>
                <td><code>{row.kind}</code></td>
                <td><span class="tag">{row.group}</span></td>
                <td>{row.subject}</td>
                <td>
                  <a
                    :for={locale <- @locales}
                    href={"/dev/emails/#{row.kind}?locale=#{locale}"}
                    style="margin-right:12px"
                  >
                    {locale}
                  </a>
                </td>
              </tr>
            </tbody>
          </table>
          <p class="muted">Sent mail (dev): <a href="/dev/mailbox">/dev/mailbox</a></p>
        </main>
      </body>
    </html>
    """
  end

  def show(assigns) do
    assigns = Map.merge(assigns, %{style: @style, headers: headers(assigns.email)})

    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="robots" content="noindex" />
        <title>{@kind} ({@locale}) · emails · dev</title>
        <style>
          {@style}
        </style>
      </head>
      <body>
        <main>
          <p><a href="/dev/emails">← All emails</a></p>
          <h1><code>{@kind}</code> <span class="tag">{@group}</span></h1>
          <p>
            <a
              :for={locale <- @locales}
              href={"/dev/emails/#{@kind}?locale=#{locale}"}
              style="margin-right:12px"
            >
              <strong :if={locale == @locale}>{locale}</strong>
              <span :if={locale != @locale}>{locale}</span>
            </a>
          </p>
          <table>
            <tr :for={{name, value} <- @headers}>
              <th style="width:200px">{name}</th>
              <td>{value}</td>
            </tr>
          </table>
          <div class="frames">
            <figure>
              <figcaption>Desktop (680 px)</figcaption>
              <iframe title="Email at desktop width" width="680" srcdoc={@email.html_body}></iframe>
            </figure>
            <figure>
              <figcaption>Phone (375 px)</figcaption>
              <iframe title="Email at phone width" width="375" srcdoc={@email.html_body}></iframe>
            </figure>
          </div>
          <h2>Text part</h2>
          <pre>{@email.text_body}</pre>
        </main>
      </body>
    </html>
    """
  end

  defp headers(email) do
    [
      {"Subject", email.subject},
      {"From", address(email.from)},
      {"To", Enum.map_join(email.to, ", ", &address/1)},
      {"Postmark stream", email.provider_options[:message_stream]}
    ] ++ Enum.sort(email.headers)
  end

  defp address({"", email}), do: email
  defp address({name, email}), do: "#{name} <#{email}>"
end
