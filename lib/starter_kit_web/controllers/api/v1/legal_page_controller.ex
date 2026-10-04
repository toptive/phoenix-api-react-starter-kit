defmodule StarterKitWeb.Api.V1.LegalPageController do
  @moduledoc "Published legal text in the request locale, with conditional GET."
  use StarterKitWeb, :controller
  alias StarterKit.Legal

  def show(conn, %{"slug" => slug}) do
    conn = skip_authorization(conn)

    case Legal.published_page(slug, locale(conn)) do
      {:ok, page} ->
        etag = ~s("#{slug}:#{page.version}:#{locale(conn)}")

        StarterKitWeb.ConditionalGet.render(conn, etag, fn conn ->
          render_data(conn, {Serializers.LegalPageSerializer, page})
        end)

      {:error, :not_found} ->
        render_error(conn, 404, :not_found)
    end
  end
end
