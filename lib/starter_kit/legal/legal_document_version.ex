defmodule StarterKit.Legal.LegalDocumentVersion do
  @moduledoc """
  An immutable version of a legal document. `titles` and `bodies` are maps keyed by
  locale; English is required. Bodies are plain text: blank lines separate paragraphs
  and lines starting with `## ` are headings (rendered safely, never as raw HTML).
  """

  use StarterKit.Schema, policy: StarterKit.Legal.LegalDocumentPolicy

  schema "legal_document_versions" do
    field :number, :integer
    field :titles, :map, default: %{}
    field :bodies, :map, default: %{}
    field :note, :string
    field :published_at, :utc_datetime
    field :created_by_id, :binary_id
    belongs_to :legal_document, StarterKit.Legal.LegalDocument

    timestamps()
  end

  @doc false
  def changeset(version, attrs) do
    version
    |> cast(attrs, [:titles, :bodies, :note])
    |> validate_english(:titles)
    |> validate_english(:bodies)
    |> validate_locale_values(:titles)
    |> validate_locale_values(:bodies)
    |> validate_locale_sizes(:titles, 255)
    |> validate_locale_sizes(:bodies, 100_000)
    |> validate_length(:note, max: 255)
    |> unique_constraint([:legal_document_id, :number])
  end

  defp validate_english(changeset, field) do
    case get_field(changeset, field) do
      %{"en" => value} when is_binary(value) and value != "" -> changeset
      _ -> add_error(changeset, field, "validation.english_required")
    end
  end

  defp validate_locale_values(changeset, field) do
    case get_field(changeset, field) do
      values when is_map(values) ->
        if Enum.all?(Map.values(values), &is_binary/1),
          do: changeset,
          else: add_error(changeset, field, "validation.invalid")

      _ ->
        changeset
    end
  end

  defp validate_locale_sizes(changeset, field, max) do
    values = get_field(changeset, field) || %{}

    if Enum.any?(Map.values(values), &(is_binary(&1) and String.length(&1) > max)),
      do: add_error(changeset, field, "validation.length_max", count: max),
      else: changeset
  end

  @doc "Title in `locale`, falling back to English."
  def title_for(%__MODULE__{titles: titles}, locale), do: pick(titles, locale)

  @doc "Body in `locale`, falling back to English."
  def body_for(%__MODULE__{bodies: bodies}, locale), do: pick(bodies, locale)

  defp pick(map, locale) do
    case Map.get(map, locale) do
      value when is_binary(value) and value != "" -> value
      _ -> Map.get(map, "en", "")
    end
  end
end
