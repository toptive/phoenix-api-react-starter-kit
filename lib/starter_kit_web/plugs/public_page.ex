defmodule StarterKitWeb.Plugs.PublicPage do
  @moduledoc """
  Public, indexable pages (the `:public` pipeline, before `:browser`).

  A request with no `Cookie` and no `Authorization` header is anonymous: nobody is
  signed in, the flash is empty and the locale comes from the path only. The response
  drops every cookie (the session and Inertia's `XSRF-TOKEN`), so the page is the same
  for every anonymous visitor and `render_public/3` answers with an ETag, `304 Not
  Modified` and a public `Cache-Control` (`cache/3`). A first visit from search or an ad stays
  cookie-free until the visitor opens a form page (sign-in, sign-up), which sets the
  session and the CSRF token as usual.

  A request that carries a cookie runs the normal browser chain (session, flash, CSRF,
  current user) and `render_public/3` marks it `private, no-store`.
  """

  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    if anonymous?(conn) do
      conn
      |> assign(:public_anonymous, true)
      |> register_before_send(&drop_cookies/1)
    else
      conn
    end
  end

  # A session already in place (tests use `init_test_session/2`) is never anonymous.
  defp anonymous?(conn) do
    get_req_header(conn, "cookie") == [] and get_req_header(conn, "authorization") == [] and
      not Map.has_key?(conn.private, :plug_session)
  end

  # Registered before the session and CSRF callbacks, so it runs after them.
  defp drop_cookies(conn), do: delete_resp_header(%{conn | resp_cookies: %{}}, "set-cookie")

  @doc """
  The cache headers of a public page, set before it renders. An anonymous full-page GET
  gets a weak ETag over the page and shared props, the asset version and the date, and
  `public, max-age=0, must-revalidate`; a matching `If-None-Match` returns
  `{:not_modified, conn}` so the page is never rendered (no SSR). Anything else (a cookie,
  an Inertia visit) is `private, no-store`.
  """
  def cache(conn, component, props) do
    conn = put_resp_header(conn, "vary", "X-Inertia, Cookie")

    if cacheable?(conn) do
      etag = etag(conn, component, props)

      conn =
        conn
        |> put_resp_header("etag", etag)
        |> put_resp_header("cache-control", "public, max-age=0, must-revalidate")

      {if(etag_matches?(conn, etag), do: :not_modified, else: :render), conn}
    else
      {:render, put_resp_header(conn, "cache-control", "private, no-store")}
    end
  end

  defp cacheable?(conn) do
    conn.assigns[:public_anonymous] == true and conn.method == "GET" and
      conn.status in [nil, 200] and get_req_header(conn, "x-inertia") == []
  end

  # `auth` is nil and `translations` is covered by `i18nVersion` for an anonymous visitor.
  # The date covers the footer year in the SSR HTML.
  defp etag(conn, component, props) do
    shared = Map.drop(conn.private[:inertia_shared] || %{}, [:auth, :translations])

    fingerprint =
      {component, props, shared, Application.get_env(:inertia, :default_version), Date.utc_today()}

    hash = :crypto.hash(:sha256, :erlang.term_to_binary(fingerprint))
    ~s(W/"#{Base.encode16(hash, case: :lower)}")
  end

  defp etag_matches?(conn, etag) do
    expected = String.replace_prefix(etag, "W/", "")

    conn
    |> get_req_header("if-none-match")
    |> Enum.flat_map(&String.split(&1, ","))
    |> Enum.any?(&((&1 |> String.trim() |> String.replace_prefix("W/", "")) in ["*", expected]))
  end
end
