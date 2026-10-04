defmodule StarterKit.I18n.Translation do
  @moduledoc """
  The runtime value of one key in one locale. `edited` turns true when an admin changes
  the value; from then on the CSV sync never overwrites it.
  """

  use StarterKit.Schema, policy: StarterKit.I18n.TranslationPolicy

  schema "translations" do
    field :key, :string
    field :locale, :string
    field :value, :string, default: ""
    field :edited, :boolean, default: false
    field :edited_by_id, :binary_id

    timestamps()
  end

  @doc false
  def edit_changeset(translation, attrs) do
    translation
    |> cast(attrs, [:value], empty_values: [])
    |> validate_length(:value, max: 20_000)
    |> put_change(:edited, true)
  end
end
