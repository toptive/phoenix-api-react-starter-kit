defmodule StarterKitWeb.Serializers.BootstrapSerializer do
  @moduledoc "The SPA's bootstrap payload, including an anonymous user."
  use Typelizer.Serializer

  alias StarterKitWeb.Serializers.{MembershipSerializer, OrganizationSerializer, UserSerializer}

  has_one :user, serializer: UserSerializer, nullable: true
  has_one :organization, serializer: OrganizationSerializer, nullable: true
  has_one :membership, serializer: MembershipSerializer, nullable: true
  has_many :organizations, serializer: OrganizationSerializer
  has_one :impersonator, serializer: UserSerializer, nullable: true
  attribute :superadmin, type: :boolean
  attribute :locale, type: :string
  attribute :locales, type: {:list, :string}
  attribute :i18n_version, type: :string
  attribute :flags, type: {:map, :boolean}

  attribute :app,
    type:
      {:object,
       name: :string,
       tenancy: {:enum, [:multi, :single]},
       signup_mode: {:enum, [:open, :invite, :closed]},
       google_enabled: :boolean,
       email_available: :boolean}

  attribute :turnstile, type: {:object, required: :boolean, site_key: {:nullable, :string}}
end

defmodule StarterKitWeb.Serializers.LocaleSerializer do
  @moduledoc "The flat translation catalogue; the endpoint returns the translations field."
  use Typelizer.Serializer

  attribute :translations, type: {:map, :string}
end

defmodule StarterKitWeb.Serializers.AuthSessionSerializer do
  @moduledoc "An issued bearer token and its owner."
  use Typelizer.Serializer

  attribute :token, type: :string
  attribute :expires_at, type: :utc_datetime
  has_one :user, serializer: StarterKitWeb.Serializers.UserSerializer
end

defmodule StarterKitWeb.Serializers.SudoSerializer do
  @moduledoc "The current token's sudo expiry."
  use Typelizer.Serializer
  attribute :sudo_until, type: :utc_datetime
end
