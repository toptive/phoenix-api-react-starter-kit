defmodule StarterKitWeb.Plugs.InertiaShare do
  @moduledoc """
  Props every page receives. All are cheap or lazy — no per-request database work
  beyond the scope that `UserAuth` already loaded.

    * `auth` — current user, organization, membership, organizations for the switcher,
      impersonation and superadmin flags (nil for guests);
    * `locale`, `locales`, `i18nVersion`;
    * `translations` — the whole catalogue, ONLY when the client does not have this
      locale+version yet (full page load, locale switch, admin edit). The client sends
      `X-I18n: <locale>:<version>` on every Inertia visit;
    * `app` — name and tenancy mode;
    * `flags` — the public feature flags (`StarterKit.Flags`, `public: true`), e.g.
      `flags.billing`;
    * `turnstile` — `required` and the public site key for `components/app/turnstile.tsx`
      (`StarterKit.AbuseProtection.widget/0`; no key while protection is off).
  """

  @behaviour Plug

  use Typelizer.InertiaPage

  import Plug.Conn
  import Inertia.Controller

  alias StarterKit.Accounts.Scope
  alias StarterKit.{I18n, Organizations}
  alias StarterKitWeb.Serializers

  shared auth:
           {:nullable,
            {:object,
             user: Serializers.UserSerializer,
             organization: Serializers.OrganizationSerializer,
             membership: Serializers.MembershipSerializer,
             organizations: {:list, Serializers.OrganizationSerializer},
             superadmin: :boolean,
             impersonator: {:nullable, Serializers.UserSerializer}}},
         locale: :string,
         locales: {:list, :string},
         i18n_version: :string,
         translations: {:optional, {:map, :string}},
         app: {:object, name: :string, tenancy: {:enum, [:multi, :single]}},
         flags: {:object, Enum.map(StarterKit.Flags.public_names(), &{&1, :boolean})},
         turnstile: {:object, required: :boolean, site_key: {:nullable, :string}}

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    locale = conn.assigns[:locale] || I18n.default_locale()
    version = I18n.version()
    scope = conn.assigns[:current_scope]

    conn
    |> assign_prop(:auth, fn -> auth(scope) end)
    |> assign_prop(:locale, locale)
    |> assign_prop(:locales, I18n.locales())
    |> assign_prop(:i18n_version, version)
    |> maybe_translations(locale, version)
    |> assign_prop(:app, %{
      name: Application.get_env(:starter_kit, :app_name, "StarterKit"),
      tenancy: Organizations.mode()
    })
    |> assign_prop(:flags, StarterKit.Flags.public())
    |> assign_prop(:turnstile, StarterKit.AbuseProtection.widget())
  end

  defp maybe_translations(conn, locale, version) do
    if get_req_header(conn, "x-i18n") == ["#{locale}:#{version}"] do
      conn
    else
      # Keys like "auth.session.tab_link" must reach i18next as written (no camelizing).
      assign_prop(
        conn,
        :translations,
        Map.new(I18n.catalog(locale), fn {k, v} -> {preserve_case(k), v} end)
      )
    end
  end

  defp auth(%Scope{user: user} = scope) when not is_nil(user) do
    %{
      user: Serializers.UserSerializer.serialize(user),
      organization: Serializers.OrganizationSerializer.serialize(scope.organization),
      membership: Serializers.MembershipSerializer.serialize(%{scope.membership | user: nil}),
      organizations:
        Serializers.OrganizationSerializer.serialize_many(
          Organizations.list_user_organizations(scope)
        ),
      superadmin: Scope.superadmin?(scope) and is_nil(scope.impersonator),
      impersonator: scope.impersonator && Serializers.UserSerializer.serialize(scope.impersonator)
    }
  end

  defp auth(_), do: nil
end
