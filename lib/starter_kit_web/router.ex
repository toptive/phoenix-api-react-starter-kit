defmodule StarterKitWeb.Router do
  @moduledoc """
  REST routes only (index show new create edit update delete). Any other verb is a
  nested resource (`POST /admin/users/:user_id/impersonation`). URLs are resource trees.
  """

  use StarterKitWeb, :router

  import Oban.Web.Router
  import StarterKitWeb.Plugs.BearerAuth, only: [require_authenticated_api_user: 2]

  alias StarterKitWeb.Plugs

  defp require_api_superadmin(conn, opts),
    do: Plugs.BearerAuth.require_superadmin(conn, opts)

  pipeline :spa do
    plug Plugs.SecurityHeaders
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :fetch_query_params
    plug Plugs.SnakeCaseParams
    plug Plugs.BearerAuth
    plug Plugs.ApiLocale
    plug Plugs.VerifyAuthorized
  end

  pipeline :api_authenticated do
    plug :require_authenticated_api_user
  end

  # No session: error messages use the default locale (the reader is a machine).
  pipeline :webhook do
    plug :accepts, ["json"]
  end

  pipeline :api_superadmin do
    plug :require_api_superadmin
  end

  pipeline :jobs_browser do
    plug :put_secure_browser_headers, %{"content-security-policy" => "default-src 'self'"}
    plug :accepts, ["html"]
    plug :fetch_session
    plug StarterKitWeb.JobsAccess
    plug :fetch_live_flash
    plug :protect_from_forgery
    plug Plugs.SecurityHeaders
  end

  # Phoenix's own dev tools (LiveDashboard, mailbox preview): default headers, which
  # allow same-origin framing (the mailbox previews emails in an iframe).
  pipeline :dev_tools do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :protect_from_forgery

    plug :put_secure_browser_headers, %{
      "content-security-policy" =>
        "default-src 'self' 'unsafe-inline' data: ws:; frame-ancestors 'self'"
    }
  end

  pipeline :bare do
    plug :put_secure_browser_headers, %{"content-security-policy" => "default-src 'self'"}
    plug :accepts, ["xml", "txt", "json", "html"]
  end

  # Infrastructure: health check, sitemap, robots (no session).
  scope "/", StarterKitWeb do
    pipe_through :bare

    get "/admin/jobs/session", JobsSessionController, :show
    get "/health", HealthController, :show
    get "/sitemap.xml", SitemapController, :show
    get "/robots.txt", RobotsController, :show
  end

  scope "/admin" do
    pipe_through :jobs_browser

    oban_dashboard("/jobs",
      csp_nonce_assign_key: :csp_nonce,
      resolver: StarterKitWeb.JobsAccess,
      on_mount: [StarterKitWeb.JobsAccess]
    )
  end

  scope "/api/v1/admin", StarterKitWeb.Api.V1.Admin, as: :api_v1_admin do
    pipe_through [:api, :api_superadmin]
    get "/dashboard", DashboardController, :show
    get "/users", UserController, :index
    get "/users/:id", UserController, :show
    put "/users/:id", UserController, :update
    post "/users/:id/impersonation", ImpersonationController, :create
    get "/organizations", OrganizationController, :index
    get "/organizations/:id", OrganizationController, :show
    get "/translations", TranslationController, :index
    put "/translations/:key", TranslationController, :update
    post "/translation-fills", TranslationFillController, :create
    get "/legal-documents", LegalDocumentController, :index
    get "/legal-documents/:slug", LegalDocumentController, :show
    post "/legal-documents/:slug/versions", LegalDocumentVersionController, :create
    post "/legal-documents/:slug/versions/:number/publication", LegalPublicationController, :create
    get "/audit-events", AuditEventController, :index
    post "/jobs-access", JobsAccessController, :create
  end

  # Signed webhooks from other services: no session, no CSRF; each controller verifies
  # the sender's signature over the raw body (Plugs.RawBody).
  scope "/webhooks", StarterKitWeb.Webhooks, as: :webhooks do
    pipe_through :webhook

    resources "/stripe/events", StripeEventController, only: [:create]
  end

  scope "/api/v1", StarterKitWeb.Api.V1, as: :api_v1 do
    pipe_through :api

    get "/bootstrap", BootstrapController, :show
    get "/locales/:locale", LocaleController, :show
    get "/legal-pages/:slug", LegalPageController, :show

    scope "/auth", Auth, as: :auth do
      post "/sessions", SessionController, :create
      post "/magic-links", MagicLinkController, :create
      post "/magic-links/:token/session", MagicLinkSessionController, :create
      post "/registrations", RegistrationController, :create
      get "/magic-links/:token", MagicLinkController, :show
      get "/google/start", GoogleStartController, :show
      get "/google/callback", GoogleCallbackController, :create
    end
  end

  scope "/api/v1/auth", StarterKitWeb.Api.V1.Auth, as: :api_v1_auth do
    pipe_through [:api, :api_authenticated]

    delete "/session", SessionController, :delete
    post "/sudo", SudoController, :create
    delete "/impersonation", ImpersonationController, :delete
  end

  scope "/api/v1", StarterKitWeb.Api.V1, as: :api_v1 do
    pipe_through :api
    get "/email-subscriptions/:token", EmailSubscriptionController, :show
    post "/email-subscriptions/:token/opt-out", EmailOptOutController, :create
    get "/invitations/:token", InvitationController, :show
  end

  scope "/api/v1", StarterKitWeb.Api.V1, as: :api_v1 do
    pipe_through [:api, :api_authenticated]
    put "/current-organization", CurrentOrganizationController, :update
    post "/organizations", OrganizationController, :create
    get "/onboarding", OnboardingController, :show
    put "/onboarding", OnboardingController, :update
    post "/invitations/:token/acceptance", InvitationAcceptanceController, :create

    scope "/settings", Settings, as: :settings do
      get "/billing", BillingController, :show
      post "/billing/checkout-session", BillingCheckoutSessionController, :create
      post "/billing/portal-session", BillingPortalSessionController, :create
      put "/profile", ProfileController, :update
      get "/email-preferences", EmailPreferenceController, :show
      put "/email-preferences", EmailPreferenceController, :update
      get "/sessions", SessionController, :index
      delete "/sessions/:id", SessionController, :delete
      put "/email", EmailController, :update
      get "/email-confirmations/:token", EmailConfirmationController, :show
      post "/email-confirmations", EmailConfirmationController, :create
      put "/password", PasswordController, :update
      get "/account", AccountController, :show
      delete "/account", AccountController, :delete
      get "/organization", OrganizationController, :show
      put "/organization", OrganizationController, :update
      get "/members", MembershipController, :index
      put "/members/:id", MembershipController, :update
      delete "/members/:id", MembershipController, :delete
      get "/invitations", InvitationController, :index
      post "/invitations", InvitationController, :create
      delete "/invitations/:id", InvitationController, :delete
    end
  end

  # JSON API with bearer authentication. Envelope: { data, meta } / { error }.
  scope "/api/v1", StarterKitWeb.Api.V1, as: :api_v1 do
    pipe_through :api

    resources "/events", EventController, only: [:create]
  end

  scope "/api/v1", StarterKitWeb.Api.V1, as: :api_v1 do
    pipe_through [:api, :api_authenticated]

    resources "/direct-uploads", DirectUploadController, only: [:create]
  end

  if Application.compile_env(:starter_kit, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :dev_tools

      live_dashboard "/dashboard", metrics: StarterKitWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview

      resources "/emails", StarterKitWeb.Dev.EmailPreviewController,
        only: [:index, :show],
        param: "kind"
    end
  end

  # Reserved backend paths never become browser pages.
  scope "/", StarterKitWeb do
    pipe_through :spa
    get "/*path", SpaController, :show
  end
end
