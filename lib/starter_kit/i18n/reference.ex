defmodule StarterKit.I18n.Reference do
  @moduledoc """
  `i18n/translations.csv` compiled into the release. It is the default value of every
  key and the input of `StarterKit.I18n.sync/0`. Recompiles when the CSV changes.
  """

  @csv_path Path.expand("../../../i18n/translations.csv", __DIR__)
  @external_resource @csv_path

  NimbleCSV.define(__MODULE__.Parser, separator: ",", escape: "\"")

  [header | rows] = @csv_path |> File.read!() |> __MODULE__.Parser.parse_string(skip_headers: false)
  ["key" | locales] = header

  @locales locales
  @rows Enum.map(rows, fn [key | values] -> {key, locales |> Enum.zip(values) |> Map.new()} end)
  @catalogs Map.new(locales, fn locale ->
              {locale,
               Map.new(@rows, fn {key, values} ->
                 value = if values[locale] in [nil, ""], do: values["en"], else: values[locale]
                 {key, value}
               end)}
            end)

  @doc "Locales present in the CSV header (the first is the default)."
  def locales, do: @locales

  @doc "All rows as `{key, %{locale => value}}` (empty string = not translated yet)."
  def rows, do: @rows

  @doc "Flat catalogue for `locale`; empty cells fall back to English."
  def catalog(locale), do: Map.get(@catalogs, locale, %{})
end
