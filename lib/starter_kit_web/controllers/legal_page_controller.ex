defmodule StarterKitWeb.LegalPageController do
  @moduledoc "Public legal pages (terms, privacy, cookies) from the database."
  use StarterKitWeb, :controller
  use Typelizer.InertiaPage

  alias StarterKit.Legal
  alias StarterKitWeb.SEO

  page "legal/show", props: [page: Serializers.LegalPageSerializer, seo: StarterKitWeb.SEO.spec()]

  def show(conn, %{"slug" => slug}) do
    conn = skip_authorization(conn)

    with true <- slug in Legal.slugs(),
         {:ok, page} <- Legal.published_page(slug, locale(conn)) do
      render_public(conn, "legal/show", %{
        page: Serializers.LegalPageSerializer.serialize(page),
        seo:
          SEO.build(conn,
            path: "/legal/#{slug}",
            title: page.title,
            description: String.slice(page.body, 0, 155),
            json_ld: [
              SEO.breadcrumb_json_ld(conn, [
                {t(conn, "app.name"), "/"},
                {page.title, "/legal/#{slug}"}
              ])
            ]
          )
      })
    else
      _ -> raise Ecto.NoResultsError, queryable: StarterKit.Legal.LegalDocument
    end
  end
end
