defmodule StarterKitWeb.Api.V1.Admin.TranslationFillController do
  @moduledoc "Superadmin translation fill API."
  use StarterKitWeb, :controller
  alias StarterKit.I18n
  alias StarterKit.I18n.Translation
  alias StarterKitWeb.ApiAuth

  def create(conn, params) do
    conn = authorize!(conn, :update, Translation)

    case I18n.fill_translations(scope(conn), Map.take(params, ["locale"])) do
      {:ok, fill} ->
        conn |> put_status(201) |> render_data({Serializers.TranslationFillSerializer, fill})

      {:error, reason} ->
        ApiAuth.error(conn, reason)
    end
  end
end
