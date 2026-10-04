defmodule StarterKitWeb.SitemapController do
  @moduledoc "sitemap.xml with every public page in every locale (hreflang alternates)."
  use StarterKitWeb, :controller

  alias StarterKit.{I18n, Legal}
  alias StarterKitWeb.Plugs.SiteIndexing
  alias StarterKitWeb.SEO

  # Empty while the indexing lock is on (Plugs.SiteIndexing).
  def show(conn, _params) do
    paths =
      if SiteIndexing.enabled?(),
        do: ["/" | Enum.map(Legal.published_slugs(), &"/legal/#{&1}")],
        else: []

    base = StarterKitWeb.Endpoint.url()

    urls =
      for path <- paths, locale <- I18n.locales() do
        alternates =
          Enum.map_join(I18n.locales(), "\n", fn alt ->
            ~s(    <xhtml:link rel="alternate" hreflang="#{alt}" href="#{base}#{SEO.localized_path(path, alt)}"/>)
          end)

        "  <url>\n    <loc>#{base}#{SEO.localized_path(path, locale)}</loc>\n#{alternates}\n  </url>"
      end

    body = """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">
    #{Enum.join(urls, "\n")}
    </urlset>
    """

    conn |> skip_authorization() |> put_resp_content_type("application/xml") |> send_resp(200, body)
  end
end
