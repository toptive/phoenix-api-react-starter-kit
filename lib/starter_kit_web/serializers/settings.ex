defmodule StarterKitWeb.Serializers.EmailPreferencesSerializer do
  @moduledoc "The user's optional mail preference."
  use Typelizer.Serializer
  attribute :optional_emails, type: :boolean
end

defmodule StarterKitWeb.Serializers.EmailChangeSerializer do
  @moduledoc "The new address awaiting confirmation."
  use Typelizer.Serializer
  attribute :email, type: :string
end

defmodule StarterKitWeb.Serializers.AccountDeletionSerializer do
  @moduledoc "The first ownership or billing blocker for account deletion."
  use Typelizer.Serializer

  attribute :blocker,
    type:
      {:nullable,
       {:object,
        reason: {:enum, [:transfer_ownership, :subscription_active]}, organization: :string}}
end
