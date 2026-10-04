defmodule StarterKitWeb.SEO do
  @moduledoc "Public SPA URL and locale mappings, with legacy head projections pending SPA delivery."

  alias StarterKit.I18n

  @doc "The typelizer type of the `seo` prop."
  def spec do
    {:object,
     title: :string,
     description: :string,
     canonical: :string,
     locale: :string,
     alternates: {:list, {:object, hreflang: :string, href: :string}},
     image: :string,
     type: :string,
     site_name: :string,
     json_ld: {:list, :map}}
  end

  @doc """
  Options: `:path` (unlocalized, e.g. "/legal/terms"), `:title`, `:description`,
  `:image` (absolute or path), `:type` ("website"), `:json_ld` (list of maps).
  """
  def build(conn, opts) do
    locale = conn.assigns[:locale] || I18n.default_locale()
    path = Keyword.fetch!(opts, :path)

    %{
      title: Keyword.fetch!(opts, :title),
      description: Keyword.get(opts, :description, ""),
      canonical: url(localized_path(path, locale)),
      locale: locale,
      alternates:
        Enum.map(I18n.locales(), &%{hreflang: &1, href: url(localized_path(path, &1))}) ++
          [%{hreflang: "x-default", href: url(localized_path(path, I18n.default_locale()))}],
      image: opts |> Keyword.get_lazy(:image, fn -> default_image(locale) end) |> absolute(),
      type: Keyword.get(opts, :type, "website"),
      site_name: Application.get_env(:starter_kit, :app_name, "StarterKit"),
      json_ld: Keyword.get(opts, :json_ld, [])
    }
  end

  @doc """
  The default social card of `locale`: `/images/og-<locale>.png`, built by `bin/og-cards.mjs`
  (falls back to the default locale's card).
  """
  # sobelow_skip ["Traversal.FileModule"]
  # The locale is checked against the configured list first; no user input reaches the path.
  def default_image(locale) do
    card = Application.app_dir(:starter_kit, "priv/static/images/og-#{locale}.png")

    if locale in I18n.locales() and File.exists?(card),
      do: "/images/og-#{locale}.png",
      else: "/images/og-#{I18n.default_locale()}.png"
  end

  @doc "`/legal/terms` in `es` → `/es/legal/terms`; the default locale has no prefix."
  def localized_path(path, locale) do
    cond do
      locale == I18n.default_locale() -> path
      path == "/" -> "/#{locale}"
      true -> "/#{locale}#{path}"
    end
  end

  @doc "JSON-LD for the organization behind the site."
  def organization_json_ld do
    %{
      "@context" => "https://schema.org",
      "@type" => "Organization",
      "name" => Application.get_env(:starter_kit, :app_name, "StarterKit"),
      "url" => url("/"),
      "logo" => url("/favicon.svg")
    }
  end

  @doc "JSON-LD `WebSite` block."
  def website_json_ld(description) do
    %{
      "@context" => "https://schema.org",
      "@type" => "WebSite",
      "name" => Application.get_env(:starter_kit, :app_name, "StarterKit"),
      "url" => url("/"),
      "description" => description
    }
  end

  @doc """
  JSON-LD `BreadcrumbList` from `[{name, path}]`, the home page first. Paths are unlocalized
  ("/legal/terms"); each item links to the page in the locale of `conn`.
  """
  def breadcrumb_json_ld(conn, crumbs) do
    locale = conn.assigns[:locale] || I18n.default_locale()

    %{
      "@context" => "https://schema.org",
      "@type" => "BreadcrumbList",
      "itemListElement" =>
        crumbs
        |> Enum.with_index(1)
        |> Enum.map(fn {{name, path}, position} ->
          %{
            "@type" => "ListItem",
            "position" => position,
            "name" => name,
            "item" => url(localized_path(path, locale))
          }
        end)
    }
  end

  defp absolute("http" <> _ = url), do: url
  defp absolute(path), do: url(path)

  @doc "Absolute public SPA URL, shared by crawler infrastructure."
  def url(path),
    do: String.trim_trailing(Application.fetch_env!(:starter_kit, :public_url), "/") <> path
end
