defmodule StarterKitWeb.Api.V1.Admin.TranslationController do
  @moduledoc "Superadmin translation API."
  use StarterKitWeb, :controller
  alias StarterKit.I18n
  alias StarterKit.I18n.Translation
  alias StarterKitWeb.ApiAuth

  def index(conn, params) do
    conn = authorize!(conn, :index, Translation)
    page = I18n.list_translations(scope(conn), params)

    render_collection(conn, page.entries, Serializers.TranslationEntrySerializer, %{
      pagination: Serializers.PaginationSerializer.serialize(page)
    })
  end

  def update(conn, %{"key" => key} = params) do
    conn = authorize!(conn, :update, Translation)

    case I18n.edit_translation(scope(conn), key, Map.take(params, ["locale", "value"])) do
      {:ok, entry} -> render_data(conn, {Serializers.TranslationEntrySerializer, entry})
      {:error, reason} -> ApiAuth.error(conn, reason)
    end
  end
end
