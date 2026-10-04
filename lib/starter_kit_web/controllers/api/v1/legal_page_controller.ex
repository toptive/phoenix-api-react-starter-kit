defmodule StarterKitWeb.Api.V1.LegalPageController do
  @moduledoc "Published legal text in the request locale, with conditional GET."
  use StarterKitWeb, :controller
  alias StarterKit.Legal

  def show(conn, %{"slug" => slug}) do
    conn = skip_authorization(conn)

    case Legal.published_page(slug, locale(conn)) do
      {:ok, page} ->
        etag = ~s("#{slug}:#{page.version}:#{locale(conn)}")

        conn =
          conn
          |> put_resp_header("etag", etag)
          |> put_resp_header("cache-control", "public, no-cache")

        if Enum.any?(
             get_req_header(conn, "if-none-match") |> Enum.flat_map(&String.split(&1, ",")),
             &(String.replace_prefix(String.trim(&1), "W/", "") in [etag, "*"])
           ),
           do: send_resp(conn, 304, ""),
           else: render_data(conn, {Serializers.LegalPageSerializer, page})

      {:error, :not_found} ->
        render_error(conn, 404, :not_found)
    end
  end
end
