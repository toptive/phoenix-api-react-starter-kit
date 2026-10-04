defmodule StarterKit.Accounts.Session do
  @moduledoc "A device's opaque bearer session. Only the token digest is persisted."
  use StarterKit.Schema

  schema "sessions" do
    field :token_hash, :binary, redact: true
    belongs_to :user, StarterKit.Accounts.User
    field :organization_id, :binary_id
    belongs_to :impersonator_user, StarterKit.Accounts.User
    belongs_to :impersonator_session, __MODULE__
    belongs_to :impersonation, StarterKit.Accounts.Impersonation
    field :authenticated_at, :utc_datetime
    field :sudo_until, :utc_datetime
    field :expires_at, :utc_datetime
    field :last_used_at, :utc_datetime
    field :revoked_at, :utc_datetime
    field :user_agent, :string
    field :ip_address, :string
    timestamps(updated_at: false)
  end
end
