defmodule StarterKit.Accounts.User do
  @moduledoc """
  A person who signs in. `role` is global (`:user` or `:superadmin`); what a user may do
  inside an organization comes from their `StarterKit.Organizations.Membership`.
  """

  use StarterKit.Schema, policy: StarterKit.Accounts.UserPolicy

  @roles [:user, :superadmin]
  @locales ~w(en es)

  schema "users" do
    field :email, :string
    field :name, :string, default: ""
    field :role, Ecto.Enum, values: @roles, default: :user
    field :locale, :string, default: "en"
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :confirmed_at, :utc_datetime
    field :google_uid, :string
    field :last_organization_id, :binary_id
    # Optional (lifecycle, marketing) mail; false after an unsubscribe.
    field :optional_emails, :boolean, default: true
    field :authenticated_at, :utc_datetime, virtual: true
    # The sign-up checkbox (terms + privacy); the proof is a LegalAcceptance per document.
    field :terms_accepted, :boolean, virtual: true, default: false

    timestamps()
  end

  @doc "Global roles."
  def roles, do: @roles

  @doc "Locales a user may pick."
  def locales, do: @locales

  @doc """
  Changeset for registering: name, email, locale and the accepted terms. No password —
  the user confirms the email with a magic link and may set a password later in settings.
  """
  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:name, :email, :locale, :terms_accepted])
    |> validate_name()
    |> validate_locale()
    |> validate_email(opts)
    |> validate_acceptance(:terms_accepted, message: "validation.terms_required")
  end

  @doc "Changeset for the first superadmin (a release task): a confirmed account, no password."
  def bootstrap_changeset(email) do
    %__MODULE__{}
    |> cast(%{email: email}, [:email])
    |> validate_email(validate_unique: true)
    |> put_change(:confirmed_at, DateTime.utc_now(:second))
  end

  @doc "Changeset for the profile page (name and locale)."
  def profile_changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :locale])
    |> validate_name()
    |> validate_locale()
  end

  @doc "Changeset for the email preferences page (optional mail on or off)."
  def email_preferences_changeset(user, attrs) do
    user
    |> cast(attrs, [:optional_emails])
    |> validate_required([:optional_emails])
  end

  @doc "Changeset for superadmins changing the global role."
  def role_changeset(user, attrs) do
    user
    |> cast(attrs, [:role])
    |> validate_required([:role])
  end

  @doc "Changeset for a user created by Google sign-in (already confirmed)."
  def google_changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :email, :locale, :google_uid])
    |> validate_required([:google_uid])
    |> validate_email(validate_unique: true)
    |> put_change(:confirmed_at, DateTime.utc_now(:second))
    |> unique_constraint(:google_uid)
  end

  @doc """
  A user changeset for changing the email.

  ## Options

    * `:validate_unique` - set to false to skip the uniqueness check (live validation).
  """
  def email_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email])
    |> validate_email(opts)
    |> validate_email_changed()
  end

  defp validate_name(changeset) do
    changeset
    |> validate_required([:name])
    |> validate_length(:name, max: 120)
  end

  defp validate_locale(changeset), do: validate_inclusion(changeset, :locale, @locales)

  defp validate_email(changeset, opts) do
    changeset =
      changeset
      |> validate_required([:email])
      |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/, message: "validation.email_format")
      |> validate_length(:email, max: 160)

    if Keyword.get(opts, :validate_unique, true) do
      changeset
      |> unsafe_validate_unique(:email, StarterKit.Repo)
      |> unique_constraint(:email)
    else
      changeset
    end
  end

  defp validate_email_changed(changeset) do
    if get_field(changeset, :email) && get_change(changeset, :email) == nil do
      add_error(changeset, :email, "validation.email_unchanged")
    else
      changeset
    end
  end

  @doc """
  A user changeset for changing the password.

  ## Options

    * `:hash_password` - hashes the password (default `true`).
  """
  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "validation.password_mismatch")
    |> validate_password(opts)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 72)
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      |> validate_length(:password, max: 72, count: :bytes)
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  @doc "Confirms the account by setting `confirmed_at`."
  def confirm_changeset(user) do
    now = DateTime.utc_now(:second)
    change(user, confirmed_at: now)
  end

  @doc """
  Verifies the password. If there is no user or the user has no password, calls
  `Bcrypt.no_user_verify/0` to avoid timing attacks.
  """
  def valid_password?(%__MODULE__{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end
end
