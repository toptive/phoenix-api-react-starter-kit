defmodule StarterKit.FrontendRulesTest do
  @moduledoc "Frontend rules the linters do not cover: file names, i18n keys, pages and API route usage."
  use ExUnit.Case, async: true

  @csv_keys StarterKit.I18n.Reference.rows() |> Enum.map(&elem(&1, 0)) |> MapSet.new()

  defp files,
    do:
      Path.wildcard("frontend/src/**/*.{ts,tsx}")
      |> Enum.reject(&String.contains?(&1, "/generated/"))

  test "React files and folders are kebab-case" do
    offenders =
      for path <- files(),
          segment <-
            path
            |> Path.relative_to("frontend/src")
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

  test "every SPA page has a route or an error component in router.tsx" do
    router = File.read!("frontend/src/router.tsx")
    pages = Path.wildcard("frontend/src/pages/**/*.tsx")
    assert pages != []

    for path <- pages do
      page = path |> Path.relative_to("frontend/src") |> Path.rootname()
      assert router =~ "@/#{page}", "#{path} has no SPA route"
    end
  end

  test "every generated route action is used or documented" do
    callers =
      (files() ++ Path.wildcard("frontend/e2e/**/*.ts") ++ Path.wildcard("frontend/scripts/*.mjs"))
      |> Enum.map_join("\n", &File.read!/1)

    documented = File.read!("docs/TYPE_CONTRACT.md")
    routes = Path.wildcard("frontend/src/api/generated/routes/**/*.ts")
    assert length(routes) > 2

    for path <- routes,
        [_, helper] <- Regex.scan(~r/export const (\w+) =/, File.read!(path)),
        [_, action] <- Regex.scan(~r/^  (\w+):/m, File.read!(path)) do
      name = "#{helper}.#{action}"
      assert callers =~ name or documented =~ "`#{name}`", "unused route: #{name}"
    end
  end

  test "SPA delivery is excluded from the generated API routes" do
    routes =
      Path.wildcard("frontend/src/api/generated/routes/**/*.ts") |> Enum.map_join("", &File.read!/1)

    refute routes =~ "/*path"
    refute routes =~ ~r/buildUrl\(\s*"\/admin\/jobs/
    assert File.read!("frontend/src/router.tsx") =~ "notFoundComponent"
  end
end
