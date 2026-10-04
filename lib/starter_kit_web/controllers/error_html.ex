defmodule StarterKitWeb.ErrorHTML do
  @moduledoc """
  Last-resort error pages (unmatched routes, crashes). Standalone HTML: no React, no
  database. Expected errors inside controllers (403, 404) render the Inertia page
  `errors/show` instead (see `StarterKitWeb.ErrorPages`).
  """

  use StarterKitWeb, :html

  alias StarterKit.I18n

  def render(template, assigns) do
    status = template |> String.split(".") |> hd()
    locale = assigns[:conn] && assigns.conn.assigns[:locale]
    title = I18n.t("errors.page.#{status}.title", %{}, locale)
    body = I18n.t("errors.page.#{status}.body", %{}, locale)
    home = I18n.t("errors.page.home", %{}, locale)

    assigns = %{status: status, title: title, body: body, home: home}

    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="robots" content="noindex" />
        <title>{@title}</title>
        <style>
          body{margin:0;min-height:100vh;display:grid;place-items:center;font-family:system-ui,sans-serif;background:Canvas;color:CanvasText}
          main{max-width:28rem;padding:2rem}
          p{line-height:1.6;opacity:.8}
          a{color:inherit;font-weight:600}
        </style>
      </head>
      <body>
        <main>
          <p>{@status}</p>
          <h1>{@title}</h1>
          <p>{@body}</p>
          <p><a href="/">{@home}</a></p>
        </main>
      </body>
    </html>
    """
  end
end
