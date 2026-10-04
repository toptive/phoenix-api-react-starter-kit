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
        (q == "" or String.contains?(entry.key, q) or
           Enum.any?(entry.values, fn {_, v} -> String.contains?(String.downcase(v.value), q) end)) and
          (is_nil(missing) or entry.values[missing].value == "")
      end)

    paginate_list(entries, params)
  end

  defp paginate_list(entries, params) do
    per_page = 50
    total = length(entries)
    total_pages = max(1, div(total + per_page - 1, per_page))

    page =
      case Integer.parse(to_string(params["page"] || "1")) do
        {n, _} -> n |> max(1) |> min(total_pages)
        :error -> 1
      end

    %{
      entries: Enum.slice(entries, (page - 1) * per_page, per_page),
      page: page,
      per_page: per_page,
      total: total,
      total_pages: total_pages
    }
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

      with {:ok, saved} <- Repo.insert_or_update(changeset) do
        Audit.record("translation.updated",
          scope: scope,
          subject: saved,
          metadata: %{key: key, locale: locale}
        )

        Catalog.broadcast_reload()
        {:ok, saved}
      end
    end
  end

  @doc """
  Fills the empty values of `locale` from English with the LLM (OpenRouter), in batches.
  Filled rows count as edited. Returns `{:ok, filled_count}`.
  """
  def fill_missing(scope, locale) do
    with locale when is_binary(locale) <- supported_locale(locale),
         false <- locale == default_locale() do
      source = catalog(default_locale())

      filled =
        locale
        |> missing_keys()
        |> Enum.chunk_every(40)
        |> Enum.flat_map(&machine_translate(&1, source, locale))

      Enum.each(filled, fn {key, value} -> update_translation(scope, key, locale, value) end)
      {:ok, length(filled)}
    else
      _ -> {:error, :unsupported_locale}
    end
  end

  defp machine_translate(batch, source, locale) do
    pairs = Map.new(batch, &{&1, source[&1]})

    case AI.translate_strings(pairs, from: default_locale(), to: locale) do
      {:ok, translated} -> Enum.filter(translated, fn {k, v} -> k in batch and v != "" end)
      {:error, _} -> []
    end
  end

  defp missing_keys(locale) do
    db =
      Repo.all(from t in Translation, where: t.locale == ^locale and t.value != "", select: t.key)

    present = MapSet.new(db)

    Reference.rows()
    |> Enum.filter(fn {key, values} ->
      values[locale] in [nil, ""] and not MapSet.member?(present, key)
    end)
    |> Enum.map(&elem(&1, 0))
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
