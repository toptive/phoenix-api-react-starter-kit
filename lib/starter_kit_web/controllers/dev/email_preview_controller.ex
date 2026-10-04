defmodule StarterKitWeb.Dev.EmailPreviewController do
  @moduledoc """
  `/dev/emails` (dev only): every notification kind in every locale, rendered through
  the real layout with sample data (`Notifications.preview/2`). Nothing is sent. Use it
  to check copy and layout after editing `i18n/translations.csv` or the layout.
  """
  use StarterKitWeb, :controller

  alias StarterKit.{I18n, Notifications}
  alias StarterKitWeb.Dev.EmailPreviewHTML

  plug :put_root_layout, false
  plug :put_layout, false
  plug :put_view, html: EmailPreviewHTML

  def index(conn, _params) do
    rows =
      for kind <- Notifications.kinds() do
        %{
          kind: kind,
          group: Notifications.group(kind),
          subject: Notifications.preview(kind, "en").subject
        }
      end

    conn |> skip_authorization() |> render(:index, rows: rows, locales: I18n.locales())
  end

  def show(conn, %{"kind" => kind} = params) do
    conn = skip_authorization(conn)
    locale = I18n.supported_locale(params["locale"]) || "en"

    if kind in Notifications.kinds() do
      render(conn, :show,
        kind: kind,
        locale: locale,
        locales: I18n.locales(),
        group: Notifications.group(kind),
        email: Notifications.preview(kind, locale)
      )
    else
      conn |> put_status(404) |> text("Unknown notification kind")
    end
  end
end
