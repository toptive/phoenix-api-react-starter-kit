defmodule StarterKit.I18n do
  @moduledoc """
  Every user-facing text, for backend (flash, errors, validation, mail) and frontend
  (i18next). One source: `i18n/translations.csv`. Runtime values: the `translations`
  table, editable by superadmins. See docs/I18N.md.

      I18n.t("flash.signed_in", %{name: "Ana"}, "es")
      I18n.t("invitations.count", %{count: 2}, "en")   # uses invitations.count_one / _other

  Placeholders use the i18next syntax `{{name}}` on both sides.
  """

  use Boundary,
    top_level?: true,
    deps: [StarterKit.Repo, StarterKit.Schema, StarterKit.Policy, StarterKit.Audit, StarterKit.AI],
    exports: [Translation, TranslationPolicy]

  import Ecto.Query

  alias StarterKit.{AI, Audit, Repo}
  alias StarterKit.I18n.{Catalog, Reference, Translation}

  @doc false
  def child_spec(opts), do: Catalog.child_spec(opts)

  @doc "Supported locales; the first one is the default."
  def locales, do: Reference.locales()

  @doc "The default locale."
  def default_locale, do: hd(locales())

  @doc "Returns `locale` when supported, else nil."
  def supported_locale(locale) when is_binary(locale) do
    locale = locale |> String.downcase() |> String.slice(0, 2)
    if locale in locales(), do: locale
  end

  def supported_locale(_), do: nil

  @doc "The runtime catalogue for `locale` (flat map, sent once per full page load)."
  def catalog(locale), do: Catalog.get(locale)

  @doc "A supported locale catalogue and the version used for its conditional GET."
  def locale_catalog(locale) do
    if locale in locales(),
      do: {:ok, %{catalog: catalog(locale), version: version()}},
      else: {:error, :not_found}
  end

  @doc "Catalogue version (changes on every edit or sync)."
  def version, do: Catalog.version()

  @doc "Translates `key`. Falls back to the default locale, then to the key itself."
  def t(key, bindings \\ %{}, locale \\ nil) do
    locale = locale || default_locale()
    bindings = Map.new(bindings)
    key = plural_key(key, bindings, locale)

    text =
      Map.get(catalog(locale), key) || Map.get(catalog(default_locale()), key) || key

    interpolate(text, bindings)
  end

  defp plural_key(key, %{count: count}, locale) do
    suffix = if count == 1, do: "_one", else: "_other"
    candidate = key <> suffix
    if Map.has_key?(catalog(locale), candidate), do: candidate, else: key
  end

  defp plural_key(key, _bindings, _locale), do: key

  defp interpolate(text, bindings) when map_size(bindings) == 0, do: text

  defp interpolate(text, bindings) do
    values = Map.new(bindings, fn {k, v} -> {to_string(k), to_string(v)} end)
    Regex.replace(~r/\{\{\s*(\w+)\s*\}\}/, text, fn whole, name -> Map.get(values, name, whole) end)
  end

  @doc """
  Translates one Ecto error. A custom message that is a catalogue key
  (`"validation.email_format"`) wins; otherwise `validation.<validation>` is used
  (`validation.required`, `validation.length_min`, …).
  """
  def translate_error({msg, opts}, locale) do
    bindings =
      opts
      |> Keyword.drop([:validation, :kind, :type])
      |> Map.new(fn {k, v} -> {k, format_binding(v)} end)

    catalog = catalog(locale || default_locale())

    key = if Map.has_key?(catalog, msg), do: msg, else: error_key(opts)

    if key && Map.has_key?(catalog, key),
      do: t(key, bindings, locale),
      else: interpolate_ecto(msg, bindings)
  end

  defp error_key(opts) do
    case {opts[:validation], opts[:constraint]} do
      {kind, _} when kind in [:length, :number] -> "validation.#{kind}_#{opts[:kind]}"
      {:unsafe_unique, _} -> "validation.unique"
      {nil, nil} -> nil
      {nil, constraint} -> "validation.#{constraint}"
      {validation, _} -> "validation.#{validation}"
    end
  end

  defp format_binding(value) when is_list(value), do: Enum.join(value, ", ")
  defp format_binding(value), do: value

  defp interpolate_ecto(msg, bindings) do
    Enum.reduce(bindings, msg, fn {k, v}, acc ->
      String.replace(acc, "%{#{k}}", to_string(v))
    end)
  end

  @doc "Changeset errors as message keys for JSON clients."
  def changeset_error_keys(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      if String.starts_with?(message, "validation."),
        do: message,
        else: error_key(opts) || "validation.invalid"
    end)
  end

  @doc "Translated API field errors, with bindings only for placeholders in the CSV key."
  def validation_details(changeset, locale) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      key =
        cond do
          String.starts_with?(message, "validation.") -> message
          opts[:validation] == :cast -> "validation.inclusion"
          true -> error_key(opts) || "validation.invalid"
        end

      field_error(key, Map.new(opts), locale)
    end)
  end

  @doc "An API field error translated from the catalogue."
  def field_error(key, bindings, locale) do
    placeholders = Regex.scan(~r/\{\{\s*(\w+)\s*\}\}/, t(key, %{}, locale))
    bindings = Map.new(bindings, fn {name, value} -> {to_string(name), format_binding(value)} end)
    bindings = Map.take(bindings, Enum.map(placeholders, &Enum.at(&1, 1)))
    error = %{key: key, message: t(key, bindings, locale)}
    if map_size(bindings) == 0, do: error, else: Map.put(error, :bindings, bindings)
  end

  @doc "All changeset errors as `%{field => first message}` (Inertia form errors)."
  def translate_changeset_errors(%Ecto.Changeset{} = changeset, locale) do
    changeset
    |> Ecto.Changeset.traverse_errors(&translate_error(&1, locale))
    |> flatten_errors()
  end

  defp flatten_errors(errors, prefix \\ nil) do
    Enum.reduce(errors, %{}, fn {field, value}, acc ->
      key = if prefix, do: "#{prefix}.#{field}", else: to_string(field)

      case value do
        [message | _] when is_binary(message) -> Map.put(acc, key, message)
        %{} = nested -> Map.merge(acc, flatten_errors(nested, key))
        _ -> acc
      end
    end)
  end

  ## Admin editor

  @doc """
  One page of keys for the admin editor. `q` searches keys and values; `missing=<locale>`
  shows keys without a value in that locale.
  """
  def list_translations(_scope, params) do
    rows = Repo.all(from t in Translation, select: {t.key, t.locale, t.value, t.edited})
    db = Map.new(rows, fn {key, locale, value, edited} -> {{key, locale}, {value, edited}} end)
    keys = Enum.uniq(Enum.map(Reference.rows(), &elem(&1, 0)) ++ Enum.map(rows, &elem(&1, 0)))
    reference = Map.new(Reference.rows())
    q = params |> Map.get("q", "") |> String.downcase() |> String.trim()
    exact_key = params["key"]
    missing = supported_locale(params["missing"])

    entries =
      keys
      |> Enum.sort()
      |> Enum.map(fn key ->
        values =
          Map.new(locales(), fn locale ->
            {value, edited} =
              Map.get(db, {key, locale}) || {get_in(reference, [key, locale]) || "", false}

            {locale, %{value: value, edited: edited}}
          end)

        %{key: key, values: values}
      end)
      |> Enum.filter(fn entry ->
        (is_nil(exact_key) or entry.key == exact_key) and
          (q == "" or String.contains?(String.downcase(entry.key), q) or
             Enum.any?(entry.values, fn {_, v} -> String.contains?(String.downcase(v.value), q) end)) and
          (is_nil(missing) or entry.values[missing].value == "")
      end)

    paginate_list(entries, params)
  end

  defp paginate_list(entries, params) do
    per_page = parse_page(params["per_page"], 25) |> max(1) |> min(100)
    total = length(entries)
    total_pages = max(1, div(total + per_page - 1, per_page))
    page = parse_page(params["page"], 1) |> max(1) |> min(1_000_000)

    %{
      entries: Enum.slice(entries, (page - 1) * per_page, per_page),
      page: page,
      per_page: per_page,
      total: total,
      total_pages: total_pages
    }
  end

  defp parse_page(value, default) do
    case Integer.parse(to_string(value)) do
      {n, ""} -> n
      _ -> default
    end
  end

  @doc "Sets the value of `key` in `locale` (marks it edited, audited, reloads every node)."
  def update_translation(scope, key, locale, value) do
    if supported_locale(locale) != locale do
      {:error, :unsupported_locale}
    else
      translation =
        Repo.get_by(Translation, key: key, locale: locale) ||
          %Translation{key: key, locale: locale}

      changeset =
        translation
        |> Translation.edit_changeset(%{value: value})
        |> Ecto.Changeset.put_change(:edited_by_id, scope.user.id)

      Repo.transact(fn -> save_translation(scope, changeset, key, locale) end)
      |> reload_on_success()
    end
  end

  defp save_translation(scope, changeset, key, locale) do
    with {:ok, saved} <- Repo.insert_or_update(changeset),
         {:ok, _} <-
           Audit.record("translation.updated",
             scope: scope,
             subject: saved,
             metadata: %{key: key, locale: locale}
           ) do
      {:ok, saved}
    end
  end

  defp reload_on_success(result) do
    case result do
      {:ok, _} -> Catalog.broadcast_reload()
      _ -> :ok
    end

    result
  end

  @doc """
  Fills the empty values of `locale` from English with the LLM (OpenRouter), in batches.
  Filled rows count as edited. Returns `{:ok, filled_count}`.
  """
  def fill_missing(scope, locale) do
    with true <- locale in locales() || {:error, :unsupported_locale},
         true <- AI.configured?() || {:error, :ai_not_configured} do
      translate_batches(scope, locale)
    end
  end

  defp translate_batches(scope, locale) do
    source = catalog(default_locale())
    batches = list_translations(scope, %{"missing" => locale, "per_page" => "100"})

    keys =
      for page <- 1..batches.total_pages,
          entry <-
            list_translations(scope, %{
              "missing" => locale,
              "per_page" => "100",
              "page" => to_string(page)
            }).entries,
          do: entry.key

    result =
      Enum.reduce_while(
        Enum.chunk_every(keys, 40),
        {:ok, %{}},
        &translate_batch(&1, &2, source, locale)
      )

    with {:ok, translated} <- result do
      Repo.transact(fn -> persist_fill(scope, locale, translated) end) |> reload_on_success()
    end
  end

  defp translate_batch(batch, {:ok, acc}, source, locale) do
    pairs = Map.new(batch, &{&1, source[&1] || &1})

    case AI.translate_strings(pairs, from: default_locale(), to: locale) do
      {:ok, translated} ->
        valid = Map.filter(translated, fn {key, value} -> key in batch and value != "" end)
        {:cont, {:ok, Map.merge(acc, valid)}}

      {:error, _} ->
        {:halt, {:error, :ai_unavailable}}
    end
  end

  defp persist_fill(scope, locale, translated) do
    with {:ok, count} <- save_translations(scope, locale, translated),
         {:ok, _} <-
           Audit.record("translation.filled",
             scope: scope,
             metadata: %{locale: locale, count: count}
           ) do
      {:ok, count}
    end
  end

  defp save_translations(scope, locale, translated) do
    Enum.reduce_while(translated, {:ok, 0}, fn {key, value}, {:ok, count} ->
      case save_filled_translation(scope, key, locale, value) do
        {:ok, :skipped} -> {:cont, {:ok, count}}
        {:ok, _} -> {:cont, {:ok, count + 1}}
        error -> {:halt, error}
      end
    end)
  end

  defp save_filled_translation(scope, key, locale, value) do
    row =
      Repo.get_by(Translation, key: key, locale: locale) || %Translation{key: key, locale: locale}

    if row.edited and row.value != "" do
      {:ok, :skipped}
    else
      changeset =
        row
        |> Translation.edit_changeset(%{value: value})
        |> Ecto.Changeset.put_change(:edited_by_id, scope.user.id)

      save_translation(scope, changeset, key, locale)
    end
  end

  @doc "One editor entry with values in CSV locale order."
  def translation_entry(scope, key) do
    # Use the full reference/table union, independently of the first editor page.
    entry = list_translations(scope, %{"key" => key})

    case Enum.find(entry.entries, &(&1.key == key)) do
      nil -> {:error, :not_found}
      entry -> {:ok, entry}
    end
  end

  @doc "Validates a single-cell API edit and returns the complete entry."
  def edit_translation(scope, key, attrs) do
    changeset =
      {%{}, %{locale: :string, value: :string}}
      |> Ecto.Changeset.cast(attrs, [:locale, :value], empty_values: [])
      |> Ecto.Changeset.validate_required([:locale])
      |> Ecto.Changeset.validate_inclusion(:locale, locales())
      |> Ecto.Changeset.validate_length(:value, max: 20_000)

    changeset =
      if Map.has_key?(attrs, "value") and is_binary(attrs["value"]),
        do: changeset,
        else: Ecto.Changeset.add_error(changeset, :value, "validation.required")

    with {:ok, values} <- Ecto.Changeset.apply_action(changeset, :update),
         {:ok, _} <- update_translation(scope, key, values.locale, values.value) do
      translation_entry(scope, key)
    end
  end

  @doc "Validates the fill locale before calling the configured AI provider."
  def fill_translations(scope, attrs) do
    changeset =
      {%{}, %{locale: :string}}
      |> Ecto.Changeset.cast(attrs, [:locale])
      |> Ecto.Changeset.validate_required([:locale])
      |> Ecto.Changeset.validate_inclusion(:locale, locales())

    changeset =
      if Ecto.Changeset.get_field(changeset, :locale) == default_locale(),
        do: Ecto.Changeset.add_error(changeset, :locale, "validation.inclusion"),
        else: changeset

    with {:ok, %{locale: locale}} <- Ecto.Changeset.apply_action(changeset, :insert),
         {:ok, count} <- fill_missing(scope, locale) do
      {:ok, %{count: count}}
    end
  end

  ## Deploy sync

  @doc """
  Brings the `translations` table in line with the CSV reference. Runs on every deploy
  (release command) and in `mix ecto.setup`.

    * inserts missing `(key, locale)` rows;
    * refreshes rows no admin edited when the CSV has a new non-empty value;
    * deletes rows no admin edited whose key left the CSV;
    * never touches edited rows.

  Returns `%{inserted: n, updated: n, deleted: n}`.
  """
  def sync do
    existing =
      Repo.all(from t in Translation, select: {t.key, t.locale, t.value, t.edited, t.id})
      |> Map.new(fn {key, locale, value, edited, id} -> {{key, locale}, {value, edited, id}} end)

    now = DateTime.utc_now(:second)

    {inserts, updates} =
      for {key, values} <- Reference.rows(), locale <- locales(), reduce: {[], []} do
        {ins, upd} ->
          csv_value = values[locale] || ""

          case Map.get(existing, {key, locale}) do
            nil ->
              row = %{
                id: Ecto.UUID.generate(),
                key: key,
                locale: locale,
                value: csv_value,
                edited: false,
                inserted_at: now,
                updated_at: now
              }

              {[row | ins], upd}

            {value, false, id} when csv_value != "" and csv_value != value ->
              {ins, [{id, csv_value} | upd]}

            _ ->
              {ins, upd}
          end
      end

    reference_keys = MapSet.new(Reference.rows(), &elem(&1, 0))

    stale_ids =
      for {{key, _locale}, {_value, false, id}} <- existing,
          not MapSet.member?(reference_keys, key),
          do: id

    Repo.transact(fn ->
      inserts |> Enum.chunk_every(1000) |> Enum.each(&Repo.insert_all(Translation, &1))

      Enum.each(updates, fn {id, value} ->
        Repo.update_all(from(t in Translation, where: t.id == ^id),
          set: [value: value, updated_at: now]
        )
      end)

      Repo.delete_all(from t in Translation, where: t.id in ^stale_ids)
      {:ok, :done}
    end)

    Catalog.broadcast_reload()
    %{inserted: length(inserts), updated: length(updates), deleted: length(stale_ids)}
  end
end
