defmodule StarterKitWeb.Serializers.AuthSerializer do
  @moduledoc "The signed-in user, device session and current tenant."
  use Typelizer.Serializer
  alias StarterKitWeb.Serializers.{MembershipSerializer, OrganizationSerializer, UserSerializer}
  has_one :user, serializer: UserSerializer, nullable: false
  has_one :organization, serializer: OrganizationSerializer, nullable: false
  has_one :membership, serializer: MembershipSerializer, nullable: false
  has_many :organizations, serializer: OrganizationSerializer
  has_one :impersonator, serializer: UserSerializer, nullable: true
  attribute :superadmin, type: :boolean
  attribute :onboarding_required, type: :boolean
  attribute :sudo_until, type: {:nullable, :utc_datetime}
  attribute :session_id, type: :string
end

defmodule StarterKitWeb.Serializers.AppConfigSerializer do
  @moduledoc "Public application configuration."
  use Typelizer.Serializer
  attribute :name, type: :string
  attribute :tenancy, type: {:enum, [:multi, :single]}
  attribute :signup_mode, type: {:enum, [:open, :invite, :closed]}
  attribute :google_enabled, type: :boolean
  attribute :email_available, type: :boolean
  attribute :public_url, type: :string
end

defmodule StarterKitWeb.Serializers.BootstrapSerializer do
  @moduledoc "The public SPA bootstrap payload."
  use Typelizer.Serializer
  has_one :auth, serializer: StarterKitWeb.Serializers.AuthSerializer, nullable: true
  has_one :app, serializer: StarterKitWeb.Serializers.AppConfigSerializer, nullable: false
  attribute :locale, type: :string
  attribute :locales, type: {:list, :string}
  attribute :i18n_version, type: :string
  has_one :flags, serializer: StarterKitWeb.Serializers.FlagsSerializer, nullable: false
  has_one :turnstile, serializer: StarterKitWeb.Serializers.TurnstileSerializer, nullable: false
end

defmodule StarterKitWeb.Serializers.AuthSessionSerializer do
  @moduledoc "An issued or refreshed bearer session."
  use Typelizer.Serializer
  attribute :token, type: {:nullable, :string}
  attribute :expires_at, type: :utc_datetime
  attribute :sudo_until, type: {:nullable, :utc_datetime}
  has_one :user, serializer: StarterKitWeb.Serializers.UserSerializer, nullable: false
  has_one :impersonator, serializer: StarterKitWeb.Serializers.UserSerializer, nullable: true
  attribute :new_account, type: :boolean
end

defmodule StarterKitWeb.Serializers.SudoWindowSerializer do
  @moduledoc "The current session's sudo expiry."
  use Typelizer.Serializer
  attribute :sudo_until, type: :utc_datetime
end

defmodule StarterKitWeb.Serializers.MagicLinkRequestSerializer do
  @moduledoc "The address to check for a sign-in link."
  use Typelizer.Serializer
  attribute :email, type: :string
  attribute :new_account, type: :boolean
end

defmodule StarterKitWeb.Serializers.MagicLinkSerializer do
  @moduledoc "A magic-link preview that never consumes the token."
  use Typelizer.Serializer
  attribute :email, type: :string
  attribute :confirmed, type: :boolean
end

defmodule StarterKitWeb.Serializers.FlagsSerializer do
  @moduledoc "The application's public feature flags."
  use Typelizer.Serializer
  attribute :billing, type: :boolean
end

defmodule StarterKitWeb.Serializers.TurnstileSerializer do
  @moduledoc "Public bot-protection configuration, without the secret key."
  use Typelizer.Serializer
  attribute :required, type: :boolean
  attribute :site_key, type: {:nullable, :string}
end
