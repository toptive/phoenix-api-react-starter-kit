defmodule StarterKitWeb.Admin.TranslationFillController do
  @moduledoc "Fill the empty texts of a locale with the LLM (OpenRouter)."
  use StarterKitWeb, :controller

  alias StarterKit.I18n
  alias StarterKit.I18n.Translation

  def create(conn, %{"translation_fill" => %{"locale" => locale}}) do
    conn = authorize!(conn, :update, Translation)

    case I18n.fill_missing(scope(conn), locale) do
      {:ok, count} -> put_flash_t(conn, :info, "flash.admin.translations_filled", %{count: count})
      {:error, _} -> put_flash_t(conn, :error, "flash.admin.translation_failed")
    end
    |> redirect(to: ~p"/admin/translations?#{%{missing: locale}}")
  end
end
