defmodule StarterKitWeb.Serializers.BillingOverviewSerializer do
  @moduledoc "The organization's plan, offers and billing access."
  use Typelizer.Serializer
  alias StarterKitWeb.Serializers
  attribute :plan, type: :string
  has_one :subscription, serializer: Serializers.SubscriptionSerializer, nullable: true
  has_many :offers, serializer: Serializers.OfferSerializer
  attribute :offer_revision, type: :string
  attribute :sales, type: {:enum, [:open, :test, :closed]}
  attribute :can_manage, type: :boolean
end

defmodule StarterKitWeb.Serializers.RedirectUrlSerializer do
  @moduledoc "The hosted Stripe checkout or portal destination."
  use Typelizer.Serializer
  attribute :url, type: :string
end

defmodule StarterKitWeb.Serializers.EventReceiptSerializer do
  @moduledoc "Acknowledges a submitted client event."
  use Typelizer.Serializer
  attribute :accepted, type: :boolean
end
