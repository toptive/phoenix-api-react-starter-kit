defmodule StarterKitWeb.SpaController do
  @moduledoc "Serves the built SPA and optional prerendered public pages without a session."
  use StarterKitWeb, :controller
  alias StarterKitWeb.Plugs.SiteIndexing

  def show(conn, %{"path" => path}) do
    conn = skip_authorization(conn)

    if reserved?(path) do
      render_error(conn, 404, :not_found)
    else
      serve(conn, path)
    end
  end

  defp reserved?([prefix | _]) when prefix in ["api", "dev", "webhooks"], do: true
  defp reserved?(["admin", "jobs" | _]), do: true
  defp reserved?(_path), do: false

  defp serve(conn, path) do
    root =
      Application.get_env(:starter_kit, :spa_static_dir) ||
        Application.app_dir(:starter_kit, "priv/static")

    # Only literal path segments are joined; traversal never reaches the filesystem.
    safe? = Enum.all?(path, &(not String.contains?(&1, ["..", "/", "\\", "\0"])))
    public = if safe?, do: Path.join([root | path] ++ ["index.html"])
    file = if public && File.regular?(public), do: public, else: Path.join(root, "index.html")

    case read_index(file) do
      {:ok, html} ->
        html =
          String.replace(
            html,
            "<script data-bootstrap>",
            ~s(<script data-bootstrap nonce="#{conn.assigns.csp_nonce}">)
          )

        html =
          if SiteIndexing.enabled?(),
            do: html,
            else: String.replace(html, "</head>", ~s(<meta name="robots" content="noindex"></head>))

        conn
        |> put_resp_content_type("text/html")
        |> put_resp_header("cache-control", "private, no-store")
        |> serve_html(html)

      {:error, _} ->
        render_error(conn, 503, :internal_error)
    end
  end

  # HTML is a trusted Vite build artifact, never user input; only a random nonce and
  # a constant indexing tag are interpolated by this controller.
  # sobelow_skip ["XSS.HTML"]
  defp serve_html(conn, content), do: html(conn, content)

  # The file is confined to the trusted build directory; path segments reject traversal.
  # sobelow_skip ["Traversal.FileModule"]
  defp read_index(file), do: File.read(file)
end
