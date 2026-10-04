defmodule StarterKit.Organizations.Membership do
  @moduledoc """
  A user's seat in an organization. `role` decides what they manage
  (`:owner`, `:admin`, `:member`); `access` decides whether they may change data
  (`:full`) or only read (`:viewer`).
  """

  use StarterKit.Schema, policy: StarterKit.Organizations.MembershipPolicy, tenant: true

  @roles [:owner, :admin, :member]
  @accesses [:full, :viewer]

  schema "memberships" do
    field :role, Ecto.Enum, values: @roles, default: :member
    field :access, Ecto.Enum, values: @accesses, default: :full

    belongs_to :organization, StarterKit.Organizations.Organization
    belongs_to :user, StarterKit.Accounts.User
    timestamps()
  end

  def roles, do: @roles
  def accesses, do: @accesses

  @doc false
  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:role, :access])
    |> validate_required([:role, :access])
    |> unique_constraint([:organization_id, :user_id])
  end
end
