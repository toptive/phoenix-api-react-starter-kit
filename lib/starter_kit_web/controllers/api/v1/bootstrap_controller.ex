defmodule StarterKitWeb.Api.V1.BootstrapController do
  @moduledoc "Public bootstrap data for the SPA, optionally personalized by a bearer token."
  use StarterKitWeb, :controller

  alias StarterKit.{AbuseProtection, Accounts, Flags, I18n, Organizations}
  alias StarterKit.Accounts.Scope

  def show(conn, _params) do
    conn = skip_authorization(conn)
    current = scope(conn)

    render_data(
      conn |> put_resp_header("cache-control", "private, no-store"),
      {Serializers.BootstrapSerializer,
       %{
         user: current && current.user,
         organization: current && current.organization,
         membership: current && %{current.membership | user: nil},
         organizations: if(current, do: Organizations.list_user_organizations(current), else: []),
         impersonator: current && current.impersonator,
         superadmin: Scope.superadmin?(current) and is_nil(current.impersonator),
         locale: locale(conn),
         locales: I18n.locales(),
         i18n_version: I18n.version(),
         flags: Flags.public(),
         turnstile: AbuseProtection.widget(),
         app: %{
           name: Application.get_env(:starter_kit, :app_name),
           tenancy: Organizations.mode(),
           signup_mode: Accounts.signup_mode(),
           google_enabled: Application.get_env(:starter_kit, :google_auth, false),
           email_available: Accounts.email_sign_in_available?()
         }
       }}
    )
  end
end
