defmodule StarterKit.Accounts.Impersonation do
  @moduledoc "A superadmin acting as another user. Every row is also an audit event."

  use StarterKit.Schema

  schema "impersonations" do
    field :reason, :string
    field :ended_at, :utc_datetime
    belongs_to :admin, StarterKit.Accounts.User
    belongs_to :target_user, StarterKit.Accounts.User

    timestamps()
  end

  @doc false
  def changeset(impersonation, attrs) do
    impersonation
    |> cast(attrs, [:reason])
    |> validate_required([:reason])
    |> validate_length(:reason, min: 5, max: 255)
  end
end
