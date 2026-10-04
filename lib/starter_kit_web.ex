defmodule StarterKitWeb do
  @moduledoc """
  The web layer: REST controllers rendering Inertia pages or `/api/v1` JSON through
  serializers. It calls context APIs only (see docs/ARCHITECTURE.md).

      use StarterKitWeb, :controller
      use StarterKitWeb, :html
  """

  use Boundary,
    deps: [
      StarterKit.Accounts,
      StarterKit.Organizations,
      StarterKit.I18n,
      StarterKit.Legal,
      StarterKit.Audit,
      StarterKit.Billing,
      StarterKit.Flags,
      StarterKit.AbuseProtection,
      StarterKit.Privacy,
      StarterKit.Analytics,
      StarterKit.Uploads,
      StarterKit.Monitoring,
      StarterKit.Notifications,
      StarterKit.Policy,
      StarterKit.Health
    ],
    exports: [Endpoint, Telemetry, Vite, RateLimit]

  def static_paths,
    do:
      ~w(assets fonts images favicon.ico favicon.svg apple-touch-icon.png icon-192.png icon-512.png site.webmanifest)

  def router do
    quote do
      use Phoenix.Router, helpers: false

      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def controller do
    quote do
      use Phoenix.Controller, formats: [:html, :json]

      import Plug.Conn
      import Inertia.Controller
      import StarterKitWeb.Authorization
      import StarterKitWeb.Responses

      alias StarterKitWeb.Serializers

      unquote(verified_routes())

      # 403/404 raised inside an action render the Inertia error page (ErrorPages).
      def action(conn, _opts),
        do: StarterKitWeb.ErrorPages.call_action(conn, __MODULE__, action_name(conn))
    end
  end

  def html do
    quote do
      use Phoenix.Component

      import Phoenix.Controller, only: [get_csrf_token: 0, view_module: 1, view_template: 1]
      import Phoenix.HTML
      import Inertia.HTML

      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: StarterKitWeb.Endpoint,
        router: StarterKitWeb.Router,
        statics: StarterKitWeb.static_paths()
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/html/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
