defmodule StarterKitWeb.Admin.TranslationController do
  @moduledoc "Search and edit every user-facing text, per locale."
  use StarterKitWeb, :controller
  use Typelizer.InertiaPage

  alias StarterKit.I18n
  alias StarterKit.I18n.Translation

  page "admin/translations/index",
    props: [
      entries: {:list, Serializers.TranslationEntrySerializer},
      pagination: Serializers.PaginationSerializer,
      filters: {:object, q: :string, missing: :string}
    ]

  def index(conn, params) do
    conn = authorize!(conn, :index, Translation)
    page = I18n.list_translations(scope(conn), params)

    entries =
      Enum.map(page.entries, fn entry ->
        %{key: entry.key, values: Enum.map(I18n.locales(), &Map.put(entry.values[&1], :locale, &1))}
      end)

    render_inertia(conn, "admin/translations/index", %{
      entries: Serializers.TranslationEntrySerializer.serialize_many(entries),
      pagination: Serializers.PaginationSerializer.serialize(page),
      filters: %{q: params["q"] || "", missing: params["missing"] || ""}
    })
  end

  def update(conn, %{"key" => key, "translation" => %{"locale" => locale, "value" => value}}) do
    conn = authorize!(conn, :update, Translation)

    case I18n.update_translation(scope(conn), key, locale, value) do
      {:ok, _} -> put_flash_t(conn, :info, "flash.admin.translation_saved")
      {:error, %Ecto.Changeset{} = changeset} -> assign_changeset_errors(conn, changeset)
      {:error, _} -> put_flash_t(conn, :error, "flash.admin.translation_failed")
    end
    |> redirect(to: ~p"/admin/translations?#{Map.take(conn.params, ["q", "missing", "page"])}")
  end
end
