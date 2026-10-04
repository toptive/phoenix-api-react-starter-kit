defmodule StarterKitWeb.Router do
  @moduledoc """
  REST routes only (index show new create edit update delete). Any other verb is a
  nested resource (`POST /admin/users/:user_id/impersonation`). URLs are resource trees.
  """

  use StarterKitWeb, :router

  import StarterKitWeb.UserAuth
  import Oban.Web.Router
  import StarterKitWeb.Plugs.BearerAuth, only: [require_authenticated_api_user: 2]

  alias StarterKitWeb.Plugs

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug Plugs.XsrfHeader
    plug :protect_from_forgery
    plug Plugs.SnakeCaseParams
    # Strict default; Plugs.SecurityHeaders replaces the CSP with the per-request nonce one.
    plug :put_secure_browser_headers, %{"content-security-policy" => "default-src 'self'"}
    plug Plugs.SecurityHeaders
    plug :fetch_current_scope_for_user
    plug Plugs.Locale
    plug :put_root_layout, html: {StarterKitWeb.Layouts, :root}
    plug Inertia.Plug
    plug Typelizer.InertiaPage.ValidateProps
    plug Plugs.InertiaShare
  end

  # Public, indexable pages: anonymous visitors get a cookie-free, cacheable page
  # (Plugs.PublicPage); a request with a cookie gets the normal browser chain.
  pipeline :public do
    plug Plugs.PublicPage
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

  # RFC 8058 one-click unsubscribe: mail clients POST with no session and no CSRF token;
  # the signed token in the URL is the authorization.
  pipeline :one_click do
    plug :accepts, ["html", "json"]
    plug :put_secure_browser_headers, %{"content-security-policy" => "default-src 'none'"}
  end

  # Public pages: a cookie-free, server-side page view (Plugs.PageViews).
  pipeline :page_views do
    plug Plugs.PageViews
  end

  pipeline :authenticated do
    plug :require_authenticated_user
    plug Plugs.VerifyAuthorized
  end

  pipeline :superadmin do
    plug :require_authenticated_user
    plug :require_superadmin
    plug Plugs.VerifyAuthorized
  end

  pipeline :localized do
    plug Plugs.PathLocale
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
    plug :accepts, ["xml", "txt", "json"]
  end

  # Infrastructure: health check, sitemap, robots (no session, no SSR).
  scope "/", StarterKitWeb do
    pipe_through :bare

    get "/health", HealthController, :show
    get "/sitemap.xml", SitemapController, :show
    get "/robots.txt", RobotsController, :show
  end

  # Public pages, server-rendered for SEO: default locale at "/…", other locales at
  # "/:locale/…" (the localized scope at the END of this file).
  scope "/", StarterKitWeb do
    pipe_through [:public, :browser, :page_views]

    get "/", HomeController, :show
    get "/legal/:slug", LegalPageController, :show
  end

  # Signed-in app.
  scope "/", StarterKitWeb do
    pipe_through [:browser, :authenticated]

    resources "/dashboard", DashboardController, only: [:show], singleton: true

    scope "/settings", Settings, as: :settings do
      resources "/profile", ProfileController, only: [:edit, :update], singleton: true
      resources "/appearance", AppearanceController, only: [:edit], singleton: true

      resources "/email-preferences", EmailPreferenceController,
        only: [:edit, :update],
        singleton: true

      resources "/sessions", SessionController, only: [:index, :delete]

      resources "/email-confirmations", EmailConfirmationController,
        only: [:show, :create],
        param: "token"

      resources "/billing", BillingController, only: [:show], singleton: true

      resources "/billing/checkout-session", BillingCheckoutSessionController,
        only: [:create],
        singleton: true

      resources "/billing/portal-session", BillingPortalSessionController,
        only: [:create],
        singleton: true
    end
  end

  # Sensitive settings need a recent sign-in (sudo mode).
  scope "/settings", StarterKitWeb.Settings, as: :settings do
    pipe_through [:browser, :authenticated, :require_sudo_mode]

    resources "/email", EmailController, only: [:edit, :update], singleton: true
    resources "/password", PasswordController, only: [:edit, :update], singleton: true
    resources "/account", AccountController, only: [:edit, :delete], singleton: true
  end

  # Superadmin area.
  scope "/admin", StarterKitWeb.Admin, as: :admin do
    pipe_through [:browser, :superadmin]

    get "/", DashboardController, :show

    resources "/users", UserController, only: [:index, :show, :update] do
      resources "/impersonation", ImpersonationController, only: [:create], singleton: true
    end

    resources "/organizations", OrganizationController, only: [:index, :show]
    resources "/translations", TranslationController, only: [:index, :update], param: "key"
    resources "/translation-fills", TranslationFillController, only: [:create]

    resources "/legal-documents", LegalDocumentController, only: [:index, :show], param: "slug" do
      resources "/versions", LegalDocumentVersionController, only: [:create], param: "number" do
        resources "/publication", LegalPublicationController, only: [:create], singleton: true
      end
    end

    resources "/audit-events", AuditEventController, only: [:index]
  end

  scope "/admin" do
    pipe_through [:browser, :superadmin]

    oban_dashboard("/oban", csp_nonce_assign_key: :csp_nonce)
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

  # Localized public pages: /es, /es/legal/terms… Last on purpose: "/:locale" matches
  # any single segment, so every other route must be tried first. PathLocale answers
  # 404 for an unknown locale and redirects the default locale to the unprefixed URL.
  # The frontend fills :locale through typelizer URL defaults (setUrlDefaults).
  scope "/:locale", StarterKitWeb, as: :localized do
    pipe_through [:localized, :public, :browser, :page_views]

    get "/", HomeController, :show
    get "/legal/:slug", LegalPageController, :show
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
end
