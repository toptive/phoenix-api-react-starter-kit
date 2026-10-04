defmodule StarterKitWeb.HomeController do
  @moduledoc "The landing page (legacy view until SPA delivery replaces it)."
  use StarterKitWeb, :controller
  use Typelizer.InertiaPage

  alias StarterKitWeb.SEO

  page "home/show", props: [seo: StarterKitWeb.SEO.spec()]

  def show(conn, _params) do
    description = t(conn, "home.seo.description")

    conn
    |> skip_authorization()
    |> render_inertia("home/show", %{
      seo:
        SEO.build(conn,
          path: "/",
          title: t(conn, "home.seo.title"),
          description: description,
          json_ld: [SEO.organization_json_ld(), SEO.website_json_ld(description)]
        )
    })
  end
end
