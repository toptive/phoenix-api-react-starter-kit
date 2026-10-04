defmodule StarterKit.FrontendRulesTest do
  @moduledoc "Frontend rules the linters do not cover: file names, i18n keys, page ↔ controller."
  use ExUnit.Case, async: true

  @csv_keys StarterKit.I18n.Reference.rows() |> Enum.map(&elem(&1, 0)) |> MapSet.new()

  defp files,
    do:
      Path.wildcard("assets/js/**/*.{ts,tsx}") |> Enum.reject(&String.contains?(&1, "/generated/"))

  test "React files and folders are kebab-case" do
    offenders =
      for path <- files(),
          segment <-
            path
            |> Path.relative_to("assets/js")
            |> Path.rootname()
            |> String.replace_suffix(".props", "")
            |> String.replace_suffix(".test", "")
            |> Path.split(),
          not Regex.match?(~r/^[a-z0-9]+(-[a-z0-9]+)*$/, segment),
          do: path

    assert Enum.uniq(offenders) == []
  end

  test "every static i18n key used in the code exists in i18n/translations.csv" do
    js_keys =
      for path <- files(),
          [_, key] <-
            Regex.scan(~r/\bt\("([A-Za-z0-9_.]+)"/, File.read!(path)) ++
              Regex.scan(~r/i18nKey="([A-Za-z0-9_.]+)"/, File.read!(path)),
          do: {path, key}

    ex_keys =
      for path <- Path.wildcard("lib/**/*.ex"),
          [_, key] <-
            Regex.scan(
              ~r/"((?:flash|validation|errors|auth|mail)\.[A-Za-z0-9_.]+)"/,
              File.read!(path)
            ),
          not String.ends_with?(key, "."),
          do: {path, key}

    missing =
      for {path, key} <- js_keys ++ ex_keys,
          not MapSet.member?(@csv_keys, key),
          do: "#{key} (#{path})"

    assert missing == [],
           "add these keys to i18n/translations.csv:\n" <> Enum.join(Enum.uniq(missing), "\n")
  end

  test "every page rendered by a controller exists, and every page is rendered" do
    rendered =
      for path <- Path.wildcard("lib/starter_kit_web/**/*.ex"),
          [_, page] <-
            Regex.scan(~r/render_(?:inertia|public|ssr)\([^"]*"([a-z0-9\/-]+)"/, File.read!(path)),
          into: MapSet.new(),
          do: page

    pages =
      for path <- Path.wildcard("assets/js/pages/**/*.tsx"),
          not String.ends_with?(path, ".props.tsx"),
          into: MapSet.new(),
          do: path |> Path.relative_to("assets/js/pages") |> Path.rootname()

    assert MapSet.difference(rendered, pages) |> MapSet.to_list() == [],
           "controllers render pages that do not exist"

    assert MapSet.difference(pages, rendered) |> MapSet.to_list() == [],
           "pages no controller renders"
  end

  # Tests render without SSR, so a render_public page the SSR bundle cannot resolve fails only
  # in production ("Page is not public" -> HTTP 500; whvisas 2026-10-02). The SSR entry resolves
  # pages through its own import.meta.glob or through the shared resolver in assets/js/inertia.tsx.
  test "every render_public page is reachable by the SSR page glob" do
    ssr = File.read!("assets/js/ssr.tsx")
    resolver = if ssr =~ ~s(from "@/inertia"), do: File.read!("assets/js/inertia.tsx"), else: ""

    globs =
      for [_, args] <- Regex.scan(~r/import\.meta\.glob(?:<[^>]*>)?\(([^)]*)\)/s, ssr <> resolver),
          [_, glob] <- Regex.scan(~r/"([^"]+)"/, args),
          do: glob_regex(glob)

    public =
      for path <- Path.wildcard("lib/starter_kit_web/**/*.ex"),
          [_, page] <- Regex.scan(~r/render_public\([^"]*"([a-z0-9\/-]+)"/, File.read!(path)),
          uniq: true,
          do: page

    assert globs != [], "no import.meta.glob found for the SSR entry"
    assert public != []

    missing =
      Enum.reject(public, fn page -> Enum.any?(globs, &Regex.match?(&1, "./pages/#{page}.tsx")) end)

    assert missing == [], "render_public pages missing from the SSR glob: #{inspect(missing)}"
  end

  defp glob_regex(glob) do
    glob
    |> Regex.escape()
    |> String.replace("\\*\\*/", "(?:.*/)?")
    |> String.replace("\\*", "[^/]*")
    |> then(&Regex.compile!("\\A" <> &1 <> "\\z"))
  end
end
