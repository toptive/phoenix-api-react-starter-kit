defmodule StarterKit.Application do
  @moduledoc false

  use Boundary,
    top_level?: true,
    deps: [
      StarterKit.Repo,
      StarterKit.I18n,
      StarterKit.Analytics,
      StarterKit.Billing,
      StarterKit.Flags,
      StarterKit.AbuseProtection,
      StarterKitWeb
    ]

  use Application

  @impl true
  def start(_type, _args) do
    StarterKitWeb.Vite.load_manifest()
    check_flags!()

    children =
      [
        StarterKitWeb.Telemetry,
        StarterKit.Repo,
        {DNSCluster, query: Application.get_env(:starter_kit, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: StarterKit.PubSub},
        {Task.Supervisor, name: StarterKit.TaskSupervisor},
        StarterKit.Analytics,
        {Oban, Application.fetch_env!(:starter_kit, Oban)},
        StarterKit.I18n,
        StarterKitWeb.RateLimit
      ] ++ ssr_children() ++ [StarterKitWeb.Endpoint]

    Supervisor.start_link(children, strategy: :one_for_one, name: StarterKit.Supervisor)
  end

  # A flag that is ON but not ready (billing without its Stripe keys, Turnstile with a
  # Cloudflare test key, …) stops the boot.
  defp check_flags! do
    if StarterKit.Flags.check_on_boot?() do
      StarterKit.Flags.check!(
        billing: &StarterKit.Billing.config_problems/0,
        turnstile: &StarterKit.AbuseProtection.config_problems/0
      )
    end
  end

  # Node workers for Inertia SSR (public pages only). One worker is enough for a small
  # app; raise SSR_POOL_SIZE only when SSR latency shows queueing. docs/PERFORMANCE.md
  defp ssr_children do
    if Application.get_env(:starter_kit, :ssr, false) do
      [
        {Inertia.SSR,
         path: Path.join(Application.app_dir(:starter_kit, "priv"), "ssr"),
         pool_size: Application.get_env(:starter_kit, :ssr_pool_size, 1)}
      ]
    else
      []
    end
  end

  @impl true
  def config_change(changed, _new, removed) do
    StarterKitWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
