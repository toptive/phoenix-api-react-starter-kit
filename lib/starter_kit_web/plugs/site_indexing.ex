defmodule StarterKitWeb.Plugs.SiteIndexing do
  @moduledoc """
  The site-wide indexing lock: the `:site_indexing` flag (env `SITE_INDEXING`,
  `0` by default in production until launch). While it is off, every response (pages,
  static files, errors) carries `x-robots-tag: noindex, nofollow`, robots.txt disallows
  everything and the sitemap is empty, so a pre-launch site never lands in a search index.

  It sits near the top of the endpoint: its before-send runs after the error one.
  """

  @behaviour Plug

  import Plug.Conn

  @doc "True when search engines may index the site."
  def enabled?, do: StarterKit.Flags.enabled?(:site_indexing)

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    if enabled?(),
      do: conn,
      else: register_before_send(conn, &put_resp_header(&1, "x-robots-tag", "noindex, nofollow"))
  end
end
