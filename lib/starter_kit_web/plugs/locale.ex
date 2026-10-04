defmodule StarterKitWeb.Plugs.Locale do
  @moduledoc """
  Picks the request locale, first match wins:

    1. the path prefix of localized public pages (`/es/...`, set by the router);
    2. `?locale=` (also remembered in the session);
    3. the signed-in user's `locale`;
    4. the session;
    5. `Accept-Language`;
    6. the default locale (first CSV column).

  An anonymous public page (`Plugs.PublicPage`) skips 2–5: the URL alone decides the
  language, so one URL is one cacheable page (`/` is the default locale, `/es` Spanish).
  """

  @behaviour Plug

  import Plug.Conn

  alias StarterKit.I18n

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%{assigns: %{public_anonymous: true}} = conn, _opts) do
    assign(conn, :locale, conn.assigns[:path_locale] || I18n.default_locale())
  end

  def call(conn, _opts) do
    query = I18n.supported_locale(conn.params["locale"])
    conn = if query, do: put_session(conn, :locale, query), else: conn

    locale =
      conn.assigns[:path_locale] || query || user_locale(conn) ||
        I18n.supported_locale(get_session(conn, :locale)) ||
        accept_language(conn) || I18n.default_locale()

    assign(conn, :locale, locale)
  end

  defp user_locale(%{assigns: %{current_scope: %{user: %{locale: locale}}}}),
    do: I18n.supported_locale(locale)

  defp user_locale(_), do: nil

  defp accept_language(conn) do
    conn
    |> get_req_header("accept-language")
    |> List.first("")
    |> String.split(",")
    |> Enum.map(&(&1 |> String.split(";") |> hd() |> String.trim()))
    |> Enum.find_value(&I18n.supported_locale/1)
  end
end
