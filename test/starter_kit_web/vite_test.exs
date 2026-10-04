defmodule StarterKitWeb.ViteTest do
  # async: false — the tags test swaps the global manifest (`:persistent_term`).
  use ExUnit.Case, async: false

  alias StarterKitWeb.Vite

  # The shape `vite build` writes: the entry imports a shared chunk, which imports a vendor
  # chunk; both chunks carry CSS. A dynamic import must not be preloaded.
  @manifest %{
    "js/app.tsx" => %{
      "file" => "app-1.js",
      "css" => ["app-1.css"],
      "imports" => ["_shared-2.js", "_vendor-3.js"],
      "dynamicImports" => ["js/pages/lazy.tsx"]
    },
    "_shared-2.js" => %{
      "file" => "shared-2.js",
      "css" => ["shared-2.css"],
      "imports" => ["_vendor-3.js"]
    },
    "_vendor-3.js" => %{
      "file" => "vendor-3.js",
      "css" => ["vendor-3.css"],
      "imports" => ["_shared-2.js"]
    },
    "js/pages/lazy.tsx" => %{"file" => "lazy-4.js", "css" => ["lazy-4.css"]}
  }

  test "collects every statically imported chunk once, dependencies first, even with a cycle" do
    files = @manifest |> Vite.imported_chunks("js/app.tsx") |> Enum.map(& &1["file"])

    assert files == ["vendor-3.js", "shared-2.js"]
  end

  test "an entry without imports has no chunks" do
    assert Vite.imported_chunks(%{"js/app.tsx" => %{"file" => "app.js"}}, "js/app.tsx") == []
  end

  test "the page links the CSS of every imported chunk and preloads only static chunks" do
    key = {Vite, :manifest}
    previous = :persistent_term.get(key, %{})
    :persistent_term.put(key, @manifest)
    on_exit(fn -> :persistent_term.put(key, previous) end)

    html = Vite.tags()

    stylesheets =
      Regex.scan(~r/rel="stylesheet" href="\/assets\/([^"]+)"/, html, capture: :all_but_first)

    assert List.flatten(stylesheets) == ["vendor-3.css", "shared-2.css", "app-1.css"]
    assert html =~ ~s(<link rel="modulepreload" href="/assets/shared-2.js">)
    refute html =~ "lazy-4"
  end
end
