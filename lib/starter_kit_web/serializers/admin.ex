defmodule StarterKitWeb.Serializers.AdminStatsSerializer do
  @moduledoc "Admin dashboard counts."
  use Typelizer.Serializer
  attribute :users, type: :integer
  attribute :organizations, type: :integer
end

defmodule StarterKitWeb.Serializers.AdminUserDetailSerializer do
  @moduledoc "A user and their organizations."
  use Typelizer.Serializer
  has_one :user, serializer: StarterKitWeb.Serializers.UserSerializer, nullable: false
  has_many :organizations, serializer: StarterKitWeb.Serializers.OrganizationSerializer
end

defmodule StarterKitWeb.Serializers.AdminOrganizationDetailSerializer do
  @moduledoc "An organization and its members."
  use Typelizer.Serializer

  has_one :organization,
    serializer: StarterKitWeb.Serializers.OrganizationSerializer,
    nullable: false

  has_many :memberships, serializer: StarterKitWeb.Serializers.MembershipSerializer
end

defmodule StarterKitWeb.Serializers.TranslationFillSerializer do
  @moduledoc "Number of filled translation cells."
  use Typelizer.Serializer
  attribute :count, type: :integer
end
