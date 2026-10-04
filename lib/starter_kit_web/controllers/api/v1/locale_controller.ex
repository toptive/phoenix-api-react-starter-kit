defmodule StarterKitWeb.Api.V1.LocaleController do
  @moduledoc "Flat locale catalogue with versioned ETags and conditional GET support."
  use StarterKitWeb, :controller
  alias StarterKit.I18n

  def show(conn, %{"locale" => requested}) do
    conn = skip_authorization(conn)

    case I18n.locale_catalog(requested) do
      {:ok, %{catalog: catalog, version: version}} ->
        etag = ~s("#{requested}:#{version}")

        conn =
          conn
          |> put_resp_header("etag", etag)
          |> put_resp_header("cache-control", "public, no-cache")

        if matches?(conn, etag),
          do: send_resp(conn, 304, ""),
          else: render_data(conn, catalog, %{locale: requested, version: version})

      {:error, :not_found} ->
        render_error(conn, 404, :not_found)
    end
  end

  defp matches?(conn, etag) do
    conn
    |> get_req_header("if-none-match")
    |> Enum.flat_map(&String.split(&1, ","))
    |> Enum.any?(&(String.replace_prefix(String.trim(&1), "W/", "") in [etag, "*"]))
  end
end
