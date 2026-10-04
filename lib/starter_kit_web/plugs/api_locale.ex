defmodule StarterKitWeb.Plugs.ApiLocale do
  @moduledoc "Cookie-free locale negotiation: query, Accept-Language, user preference, default."
  @behaviour Plug
  import Plug.Conn
  alias StarterKit.I18n

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    locale =
      I18n.supported_locale(conn.query_params["locale"]) || accept_language(conn) ||
        user_locale(conn) || I18n.default_locale()

    assign(conn, :locale, locale)
  end

  defp user_locale(%{assigns: %{current_user: %{locale: locale}}}),
    do: I18n.supported_locale(locale)

  defp user_locale(_conn), do: nil

  defp accept_language(conn) do
    conn
    |> get_req_header("accept-language")
    |> Enum.join(",")
    |> String.split(",")
    |> Enum.map(&language/1)
    |> Enum.sort_by(&elem(&1, 1), :desc)
    |> Enum.find_value(fn {locale, quality} ->
      if quality > 0, do: I18n.supported_locale(locale)
    end)
  end

  defp language(value) do
    case String.split(String.trim(value), ";q=") do
      [locale, q] ->
        quality =
          case Float.parse(q) do
            {number, ""} when number >= 0 and number <= 1 -> number
            _ -> 0.0
          end

        {locale, quality}

      [locale] ->
        {locale, 1.0}
    end
  end
end
