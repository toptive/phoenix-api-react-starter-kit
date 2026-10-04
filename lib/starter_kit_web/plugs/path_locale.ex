defmodule StarterKitWeb.Plugs.PathLocale do
  @moduledoc """
  For the localized public scope (`/:locale/…`): sets the request locale from the path.

    * a supported, non-default locale (`/es`) → `assigns.path_locale`;
    * the default locale (`/en/legal/terms`) → 301 to the unprefixed URL (one canonical URL);
    * anything else (`/xx`) → 404.
  """

  @behaviour Plug

  import Plug.Conn
  import Phoenix.Controller

  alias StarterKit.I18n

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%{path_params: %{"locale" => locale}} = conn, _opts) do
    cond do
      locale == I18n.default_locale() ->
        rest = conn.path_info |> tl() |> Enum.join("/")
        conn |> put_status(301) |> redirect(to: "/" <> rest) |> halt()

      I18n.supported_locale(locale) == locale ->
        assign(conn, :path_locale, locale)

      true ->
        # Runs before the :browser pipeline, so the format is not set yet.
        conn
        |> put_format("html")
        |> put_status(404)
        |> put_view(StarterKitWeb.ErrorHTML)
        |> render(:"404")
        |> halt()
    end
  end

  def call(conn, _opts), do: conn
end
