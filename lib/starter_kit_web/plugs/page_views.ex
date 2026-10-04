defmodule StarterKitWeb.Plugs.PageViews do
  @moduledoc """
  Server-side product analytics for public pages: no cookie, no client SDK, no visitor id.

  A successful HTML GET (or an Inertia visit) sends `public_page_viewed` with the page type
  (`home.show`), the locale, the path, the referrer host and `utm_*`. Crawlers, prefetches
  and Inertia partial reloads are skipped. The event is anonymous even for a signed-in user:
  `Analytics` gives it a throwaway id and no person profile. The plug sets no header and no
  cookie, so a cookie-free, cacheable page stays one.
  """
  @behaviour Plug
  import Plug.Conn
  require Logger

  # The source only: OTP 28 recompiles a regex kept in a module attribute on every use.
  @bots "bot|crawl|spider|slurp|facebookexternalhit|facebot|preview|headless|lighthouse|pagespeed|pingdom|uptime|monitor|curl|wget|python-requests|httpclient|go-http|java/|axios|node-fetch|scrapy|okhttp|libwww"

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts), do: register_before_send(conn, &record/1)

  defp record(%{status: 200, method: "GET"} = conn) do
    if human?(conn) and page?(conn) do
      StarterKit.Analytics.track("public_page_viewed", nil, page_props(conn))
    end

    conn
  rescue
    # An analytics problem must never break a public response; never log request data.
    _ ->
      Logger.warning("page view tracking unavailable")
      conn
  end

  defp record(conn), do: conn

  defp page?(conn) do
    (html?(conn) or get_req_header(conn, "x-inertia") != []) and
      get_req_header(conn, "x-inertia-partial-data") == []
  end

  defp page_props(conn) do
    query = fetch_query_params(conn).query_params

    %{
      page_type: page_type(conn),
      locale: conn.assigns[:locale],
      path: conn.request_path,
      referrer_domain: referrer_domain(conn),
      utm_source: param(query, "utm_source"),
      utm_medium: param(query, "utm_medium"),
      utm_campaign: param(query, "utm_campaign")
    }
  end

  defp page_type(conn) do
    controller =
      case conn.private[:phoenix_controller] do
        nil -> "unknown"
        module -> module |> Module.split() |> List.last() |> String.replace_suffix("Controller", "")
      end

    Macro.underscore(controller) <> "." <> to_string(conn.private[:phoenix_action])
  end

  defp human?(conn) do
    case get_req_header(conn, "user-agent") do
      [agent | _] ->
        byte_size(agent) <= 1024 and not Regex.match?(bots(), agent) and not prefetch?(conn)

      [] ->
        false
    end
  end

  defp bots do
    case :persistent_term.get({__MODULE__, :bots}, nil) do
      nil ->
        regex = Regex.compile!(@bots, "i")
        :persistent_term.put({__MODULE__, :bots}, regex)
        regex

      regex ->
        regex
    end
  end

  defp prefetch?(conn) do
    get_req_header(conn, "purpose") == ["prefetch"] or get_req_header(conn, "sec-purpose") != []
  end

  defp html?(conn) do
    case get_resp_header(conn, "content-type") do
      [type | _] -> String.starts_with?(type, "text/html")
      [] -> false
    end
  end

  # Only the host leaves the app: never the referrer path or query (search terms, tokens).
  defp referrer_domain(conn) do
    with [ref | _] <- get_req_header(conn, "referer"),
         {:ok, %URI{host: host}} when is_binary(host) <- URI.new(ref),
         host = bare(host),
         false <- host in [bare(conn.host), bare(own_host())] do
      host
    else
      _ -> nil
    end
  end

  defp bare(host), do: host |> String.downcase() |> String.replace_prefix("www.", "")

  defp own_host do
    Application.fetch_env!(:starter_kit, :public_url) |> URI.parse() |> Map.get(:host)
  end

  defp param(query, key) do
    case query[key] do
      value when is_binary(value) and byte_size(value) in 1..80 -> value
      _ -> nil
    end
  end
end
