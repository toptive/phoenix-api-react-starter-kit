defmodule StarterKitWeb.Api.V1.LocaleController do
  @moduledoc "Flat locale catalogue with versioned ETags and conditional GET support."
  use StarterKitWeb, :controller
  alias StarterKit.I18n

  def show(conn, %{"locale" => requested}) do
    conn = skip_authorization(conn)

    case I18n.locale_catalog(requested) do
      {:ok, %{catalog: catalog, version: version}} ->
        etag = ~s("#{requested}:#{version}")

        StarterKitWeb.ConditionalGet.render(conn, etag, fn conn ->
          render_data(conn, catalog, %{locale: requested, version: version})
        end)

      {:error, :not_found} ->
        render_error(conn, 404, :not_found)
    end
  end
end
