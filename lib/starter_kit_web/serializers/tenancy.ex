defmodule StarterKitWeb.Serializers.InvitationPreviewSerializer do
  @moduledoc "Public invitation information, without its secret token."
  use Typelizer.Serializer
  attribute :organization, type: :string
  attribute :email, type: :string
  attribute :role, type: {:enum, [:owner, :admin, :member]}
  attribute :access, type: {:enum, [:full, :viewer]}
  attribute :email_matches, type: :boolean
  attribute :expires_at, type: :utc_datetime
end

defmodule StarterKitWeb.Serializers.OnboardingSerializer do
  @moduledoc "The current organization's onboarding state."
  use Typelizer.Serializer
  attribute :organization_name, type: :string
  attribute :required, type: :boolean
end

defmodule StarterKitWeb.Serializers.OrganizationSettingsSerializer do
  @moduledoc "Organization details and the caller's edit permission."
  use Typelizer.Serializer

  has_one :organization,
    serializer: StarterKitWeb.Serializers.OrganizationSerializer,
    nullable: false

  attribute :can_edit, type: :boolean
end

defmodule StarterKitWeb.Serializers.EmailSubscriptionSerializer do
  @moduledoc "The optional email subscription behind a signed token."
  use Typelizer.Serializer
  attribute :email, type: :string
  attribute :subscribed, type: :boolean
end
