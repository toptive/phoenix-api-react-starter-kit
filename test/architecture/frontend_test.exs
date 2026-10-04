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

  test "public API infrastructure has no Inertia caching, SSR or server page views" do
    source = File.read!("lib/starter_kit_web/router.ex")
    refute source =~ "Plugs.PublicPage"
    refute source =~ "Plugs.PageViews"
    refute File.read!("lib/starter_kit/application.ex") =~ "Inertia.SSR"
    refute File.read!("lib/starter_kit_web/responses.ex") =~ "render_public"

    for name <- ~w(health sitemap robots) do
      controller = File.read!("lib/starter_kit_web/controllers/#{name}_controller.ex")
      refute controller =~ "Inertia"
      refute controller =~ "render_public"
    end
  end
end
