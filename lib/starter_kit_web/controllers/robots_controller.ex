defmodule StarterKitWeb.RobotsController do
  @moduledoc """
  robots.txt. Public pages are indexable; the app, admin and API are not. Search and
  AI-answer crawlers get their own groups (a named group replaces `*` for that bot).
  AI-training crawlers are allowed only when listed in
  `config :starter_kit, :allowed_training_bots`. While the indexing lock is on
  (`Plugs.SiteIndexing`), everything is disallowed.
  """
  use StarterKitWeb, :controller

  alias StarterKitWeb.Plugs.SiteIndexing

  @search ~w(Googlebot Bingbot OAI-SearchBot ChatGPT-User Claude-SearchBot Claude-User PerplexityBot Perplexity-User)
  @training ~w(GPTBot ClaudeBot Google-Extended CCBot)
  @private ~w(/admin /api /dashboard /onboarding /settings /session /registration /magic-links /invitations /auth /email-subscriptions)

  def show(conn, _params) do
    body = if SiteIndexing.enabled?(), do: indexed(), else: "User-agent: *\nDisallow: /\n"

    conn |> skip_authorization() |> put_resp_content_type("text/plain") |> send_resp(200, body)
  end

  defp indexed do
    allowed_training = Application.get_env(:starter_kit, :allowed_training_bots, @training)

    groups =
      Enum.map(["*" | @search], &group(&1, true)) ++
        Enum.map(@training, &group(&1, &1 in allowed_training))

    Enum.join(groups, "\n") <> "\nSitemap: #{url(~p"/sitemap.xml")}\n"
  end

  defp group(agent, true),
    do: "User-agent: #{agent}\nAllow: /\n" <> Enum.map_join(@private, "", &"Disallow: #{&1}\n")

  defp group(agent, false), do: "User-agent: #{agent}\nDisallow: /\n"
end
