defmodule StarterKit.Organizations.Organization do
  @moduledoc "The tenant. Every tenant row carries `organization_id`."

  use StarterKit.Schema, policy: StarterKit.Organizations.OrganizationPolicy

  schema "organizations" do
    field :name, :string
    field :slug, :string
    field :personal, :boolean, default: false
    field :onboarded_at, :utc_datetime

    has_many :memberships, StarterKit.Organizations.Membership
    timestamps()
  end

  @doc false
  def changeset(organization, attrs) do
    organization
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, min: 2, max: 80)
  end

  @doc """
  Finishes onboarding. The name is optional: a blank name (a skipped step) keeps the
  current one.
  """
  def onboarding_changeset(organization, attrs) do
    attrs = Map.reject(attrs, fn {key, value} -> to_string(key) == "name" and blank?(value) end)

    organization
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, min: 2, max: 80)
    |> put_change(:onboarded_at, DateTime.utc_now(:second))
  end

  defp blank?(value), do: is_nil(value) or (is_binary(value) and String.trim(value) == "")

  @doc false
  def create_changeset(organization, attrs) do
    organization
    |> changeset(attrs)
    |> put_slug()
    |> unique_constraint(:slug)
  end

  defp put_slug(changeset) do
    case get_field(changeset, :slug) do
      nil ->
        base =
          (get_field(changeset, :name) || "org")
          |> String.downcase()
          |> String.normalize(:nfd)
          |> String.replace(~r/[^a-z0-9]+/u, "-")
          |> String.trim("-")
          |> String.slice(0, 40)

        suffix = :crypto.strong_rand_bytes(3) |> Base.encode16(case: :lower)
        put_change(changeset, :slug, if(base == "", do: suffix, else: "#{base}-#{suffix}"))

      _ ->
        changeset
    end
  end
end
