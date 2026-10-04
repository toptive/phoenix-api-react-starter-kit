defmodule StarterKitWeb.PlaceholderTest do
  @moduledoc """
  Launch safety: a product must not ship the template's placeholders — its name, its
  `CHANGE_ME` hosts, its favicon, icons and social cards, or Phoenix's default copy.

  Inside the template (the `.template-repo` marker, deleted by `bin/rename`) the launch
  checks are skipped, and one test keeps the recorded fingerprints current instead.
  """

  use ExUnit.Case, async: true

  @template? File.exists?(".template-repo")
  @product_only if @template?, do: "the template itself: its placeholders are expected", else: false

  # Built from parts, so bin/rename does not rewrite them here.
  @template_name "Starter" <> "Kit"
  @phoenix_defaults ["Peace of mind from prototype to production", "phoenix" <> "framework.org"]

  # SHA-256 (first 16 hex digits) of the template's brand files. Regenerate them in a
  # product with bin/icons (after a new favicon.svg) and bin/og-cards.mjs.
  @template_files %{
    "priv/static/favicon.svg" => "50d767d1b199c3c8",
    "priv/static/favicon.ico" => "7d0c55526c6dc530",
    "priv/static/apple-touch-icon.png" => "d871bd8b6fb80a77",
    "priv/static/icon-192.png" => "2f4c99002346d7da",
    "priv/static/icon-512.png" => "952d4ce07d3b3e9b",
    "priv/static/images/mail/logo.png" => "939da0a282a71b6c",
    "priv/static/images/og-en.png" => "24c3697524c0d1f2",
    "priv/static/images/og-es.png" => "c9b9a5d27ae10303"
  }

  # The files a visitor, a crawler or a mail client can see, plus the config behind them.
  @shipped_globs [
    "lib/**/*.{ex,heex}",
    "assets/js/**/*.{ts,tsx}",
    "assets/css/**/*.css",
    "i18n/**/*.{csv,json}",
    "config/**/*.{exs,yml}",
    "priv/static/*.{svg,webmanifest,txt}"
  ]

  defp fingerprint(path),
    do: :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower) |> binary_part(0, 16)

  defp shipped_files_containing(text) do
    for glob <- @shipped_globs,
        path <- Path.wildcard(glob),
        File.read!(path) =~ text,
        do: path
  end

  @tag skip: @product_only
  test "the template name is gone (run bin/rename)" do
    assert shipped_files_containing(@template_name) == []
  end

  @tag skip: @product_only
  test "the public host and the sender are real (config/deploy.yml)" do
    deploy = File.read!("config/deploy.yml")

    for key <- ~w(host PHX_HOST MAIL_FROM) do
      [value] = Regex.run(~r/^\s*#{key}:\s*(\S+)/m, deploy, capture: :all_but_first)
      refute value =~ ~r/CHANGE_ME|example\.com/, "#{key} is still #{value}"
    end
  end

  @tag skip: @product_only
  test "the favicon, the icons and the social cards are the product's own" do
    unchanged = for {path, hash} <- @template_files, fingerprint(path) == hash, do: path

    assert unchanged == [],
           "still the template files (new favicon.svg → bin/icons; new name or theme → bin/og-cards.mjs)"
  end

  @tag skip: @product_only
  test "no Phoenix default copy ships" do
    for text <- @phoenix_defaults, do: assert(shipped_files_containing(text) == [], text)
  end

  if @template? do
    test "the recorded template fingerprints match the template files" do
      for {path, hash} <- @template_files do
        assert fingerprint(path) == hash, "update the fingerprint of #{path}"
      end
    end
  end
end
