defmodule StarterKitWeb.Serializers.UserSerializer do
  @moduledoc "A user as the UI sees it."
  use Typelizer.Serializer, schema: StarterKit.Accounts.User

  attributes [:id, :name, :email, :role, :locale, :confirmed_at, :inserted_at]
  attribute :has_password, type: :boolean, value: &(not is_nil(&1.hashed_password))
end

defmodule StarterKitWeb.Serializers.OrganizationSerializer do
  @moduledoc "An organization (tenant)."
  use Typelizer.Serializer, schema: StarterKit.Organizations.Organization

  attributes [:id, :name, :slug, :personal]
end

defmodule StarterKitWeb.Serializers.MembershipSerializer do
  @moduledoc "A seat in an organization, with its user when loaded."
  use Typelizer.Serializer, schema: StarterKit.Organizations.Membership

  attributes [:id, :role, :access, :inserted_at]
  has_one :user, serializer: StarterKitWeb.Serializers.UserSerializer, nullable: true
end

defmodule StarterKitWeb.Serializers.InvitationSerializer do
  @moduledoc "A pending invitation (never the token)."
  use Typelizer.Serializer, schema: StarterKit.Organizations.Invitation

  attributes [:id, :email, :role, :access, :expires_at, :inserted_at]
end

defmodule StarterKitWeb.Serializers.SessionSerializer do
  @moduledoc "A signed-in device (a session token row, without the token)."
  use Typelizer.Serializer, schema: StarterKit.Accounts.Session

  attribute :id, type: :string, value: & &1.session.id
  attribute :user_agent, type: {:nullable, :string}, value: & &1.session.user_agent
  attribute :ip_address, type: {:nullable, :string}, value: & &1.session.ip_address

  attribute :authenticated_at,
    type: {:nullable, :utc_datetime},
    value: & &1.session.authenticated_at

  attribute :inserted_at, type: :utc_datetime, value: & &1.session.inserted_at

  attribute :current, type: :boolean, value: & &1.current
end

defmodule StarterKitWeb.Serializers.PaginationSerializer do
  @moduledoc "Pagination metadata of a `Repo.paginate/3` page."
  use Typelizer.Serializer

  attribute :page, type: :integer
  attribute :per_page, type: :integer
  attribute :total, type: :integer
  attribute :total_pages, type: :integer
end

defmodule StarterKitWeb.Serializers.AdminOrganizationSerializer do
  @moduledoc "An organization row in the admin list, with its member count."
  use Typelizer.Serializer

  attribute :id, type: :string, value: & &1.organization.id
  attribute :name, type: :string, value: & &1.organization.name
  attribute :slug, type: :string, value: & &1.organization.slug
  attribute :members, type: :integer
  attribute :inserted_at, type: :utc_datetime, value: & &1.organization.inserted_at
end

defmodule StarterKitWeb.Serializers.TranslationValueSerializer do
  @moduledoc "The value of a key in one locale."
  use Typelizer.Serializer

  attribute :locale, type: :string
  attribute :value, type: :string
  attribute :edited, type: :boolean
end

defmodule StarterKitWeb.Serializers.TranslationEntrySerializer do
  @moduledoc "One key in the translations editor, with its value per locale."
  use Typelizer.Serializer

  attribute :key, type: :string

  has_many :values,
    serializer: StarterKitWeb.Serializers.TranslationValueSerializer,
    value: fn entry ->
      Enum.map(StarterKit.I18n.locales(), &Map.put(entry.values[&1], :locale, &1))
    end
end

defmodule StarterKitWeb.Serializers.AuditEventSerializer do
  @moduledoc "An audit log row."
  use Typelizer.Serializer, schema: StarterKit.Audit.AuditEvent

  attributes [
    :id,
    :action,
    :actor_id,
    :impersonator_id,
    :organization_id,
    :subject_type,
    :subject_id,
    :metadata,
    :inserted_at
  ]

  attribute :actor_email, type: {:nullable, :string}
end

defmodule StarterKitWeb.Serializers.LegalPageSerializer do
  @moduledoc "A published legal page in one locale."
  use Typelizer.Serializer

  attribute :slug, type: :string
  attribute :title, type: :string
  attribute :body, type: :string
  attribute :version, type: :integer
  attribute :published_at, type: :utc_datetime
end

defmodule StarterKitWeb.Serializers.LegalDocumentVersionSerializer do
  @moduledoc "A version of a legal document (admin)."
  use Typelizer.Serializer, schema: StarterKit.Legal.LegalDocumentVersion

  attributes [:id, :number, :note, :published_at, :inserted_at]
  attribute :titles, type: {:map, :string}
  attribute :bodies, type: {:map, :string}
end

defmodule StarterKitWeb.Serializers.LegalDocumentSerializer do
  @moduledoc "A legal document with its versions (admin)."
  use Typelizer.Serializer, schema: StarterKit.Legal.LegalDocument

  attributes [:id, :slug, :published_version_id]
  has_many :versions, serializer: StarterKitWeb.Serializers.LegalDocumentVersionSerializer
end

defmodule StarterKitWeb.Serializers.DirectUploadSerializer do
  @moduledoc "Where and how the browser uploads a file."
  use Typelizer.Serializer

  attribute :url, type: :string
  attribute :key, type: :string
  attribute :method, type: :string
  attribute :headers, type: {:map, :string}
end

defmodule StarterKitWeb.Serializers.SubscriptionSerializer do
  @moduledoc "The organization's subscription as the billing page shows it (no Stripe ids)."
  use Typelizer.Serializer, schema: StarterKit.Billing.Subscription

  alias StarterKit.Billing.Subscription

  attributes [:plan, :offer_id, :status, :current_period_end, :cancel_at_period_end, :paused]
  attribute :paid, type: :boolean, value: &Subscription.paid?/1
end

defmodule StarterKitWeb.Serializers.OfferSerializer do
  @moduledoc "A paid offer from the server config: the exact price Checkout charges."
  use Typelizer.Serializer

  attribute :id, type: :string
  attribute :plan, type: :string
  attribute :interval, type: {:enum, ["month", "year"]}
  attribute :amount_cents, type: :integer
  attribute :currency, type: :string
end
