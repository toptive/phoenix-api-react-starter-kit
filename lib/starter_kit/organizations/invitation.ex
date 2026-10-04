defmodule StarterKit.Organizations.Invitation do
  @moduledoc """
  An emailed invitation to join an organization. Only the SHA-256 of the token is
  stored; the raw token travels in the email link. Valid for seven days, single use.
  """

  use StarterKit.Schema, policy: StarterKit.Organizations.InvitationPolicy, tenant: true

  alias StarterKit.Organizations.Membership

  @validity_days 7

  schema "invitations" do
    field :email, :string
    field :role, Ecto.Enum, values: Membership.roles(), default: :member
    field :access, Ecto.Enum, values: Membership.accesses(), default: :full
    field :token_hash, :binary, redact: true
    field :expires_at, :utc_datetime
    field :accepted_at, :utc_datetime

    belongs_to :organization, StarterKit.Organizations.Organization
    belongs_to :invited_by, StarterKit.Accounts.User
    timestamps()
  end

  @doc false
  def changeset(invitation, attrs) do
    invitation
    |> cast(attrs, [:email, :role, :access])
    |> validate_required([:email, :role, :access])
    |> update_change(:email, &(&1 |> String.trim() |> String.downcase()))
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/, message: "validation.email_format")
    |> validate_exclusion(:role, [:owner], message: "validation.invitation_owner")
    |> unique_constraint([:organization_id, :email],
      name: :invitations_pending_email_index,
      message: "validation.invitation_pending"
    )
  end

  @doc "Builds the raw token and puts its hash and expiry on the changeset."
  def put_token(changeset) do
    token = :crypto.strong_rand_bytes(32)

    changeset =
      changeset
      |> put_change(:token_hash, hash(token))
      |> put_change(
        :expires_at,
        DateTime.utc_now(:second) |> DateTime.add(@validity_days, :day)
      )

    {Base.url_encode64(token, padding: false), changeset}
  end

  @doc "Hash of a raw token (for lookups)."
  def hash(token), do: :crypto.hash(:sha256, token)

  @doc "Decodes the token from a URL."
  def decode(encoded) do
    case Base.url_decode64(encoded, padding: false) do
      {:ok, token} -> {:ok, hash(token)}
      :error -> :error
    end
  end

  @doc "True while pending and not expired."
  def open?(%__MODULE__{accepted_at: nil, expires_at: expires_at}),
    do: DateTime.after?(expires_at, DateTime.utc_now())

  def open?(_), do: false
end
