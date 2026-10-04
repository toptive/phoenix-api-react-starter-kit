defmodule StarterKitWeb.Vite do
  @moduledoc """
  Script and stylesheet tags for the Vite bundle.

    * dev — points at the Vite dev server (`VITE_DEV_SERVER`, default
      http://127.0.0.1:5173) with HMR and the React Refresh preamble;
    * prod — reads `priv/static/assets/.vite/manifest.json` once at boot and emits the
      hashed files, their CSS and `modulepreload` links for imported chunks.
  """

  @entry "js/app.tsx"
  @key {__MODULE__, :manifest}

  # sobelow_skip ["Traversal.FileModule"]
  # The path is fixed (the app's own priv dir); no user input reaches it.
  @doc "Loads the manifest into `:persistent_term` (prod) and sets the Inertia asset version."
  def load_manifest do
    unless dev_server?() do
      path = Application.app_dir(:starter_kit, "priv/static/assets/.vite/manifest.json")

      manifest =
        case File.read(path) do
          {:ok, json} -> Jason.decode!(json)
          {:error, _} -> %{}
        end

      :persistent_term.put(@key, manifest)

      version =
        :crypto.hash(:md5, :erlang.term_to_binary(manifest))
        |> Base.encode16(case: :lower)
        |> binary_part(0, 12)

      Application.put_env(:inertia, :default_version, version)
    end

    :ok
  end

  @doc "True in dev when the Vite dev server serves the assets."
  def dev_server?, do: Application.get_env(:starter_kit, :vite_dev_server) != nil

  @doc "The HTML for `<head>`. `nonce` is the request's CSP nonce (inline preamble in dev)."
  def tags(nonce \\ nil) do
    if dev_server?(), do: dev_tags(nonce), else: prod_tags()
  end

  defp dev_tags(nonce) do
    origin = Application.get_env(:starter_kit, :vite_dev_server)

    """
    <script type="module" nonce="#{nonce}">
    import RefreshRuntime from "#{origin}/assets/@react-refresh"
    RefreshRuntime.injectIntoGlobalHook(window)
    window.$RefreshReg$ = () => {}
    window.$RefreshSig$ = () => (type) => type
    window.__vite_plugin_react_preamble_installed__ = true
    </script>
    <script type="module" src="#{origin}/assets/@vite/client"></script>
    <script type="module" src="#{origin}/assets/#{@entry}"></script>
    """
  end

  defp prod_tags do
    manifest = :persistent_term.get(@key, %{})

    case Map.get(manifest, @entry) do
      nil ->
        "<!-- vite manifest missing: run `pnpm build` -->"

      entry ->
        chunks = imported_chunks(manifest, @entry)

        # CSS of shared chunks belongs to the page too: Vite lists it on the chunk, not on
        # the entry, so a second entry (or a split vendor chunk) would lose its styles.
        css =
          (chunks ++ [entry])
          |> Enum.flat_map(&(&1["css"] || []))
          |> Enum.uniq()
          |> Enum.map_join("\n", &~s(<link rel="stylesheet" href="/assets/#{&1}">))

        preloads =
          chunks
          |> Enum.map(& &1["file"])
          |> Enum.reject(&is_nil/1)
          |> Enum.map_join("\n", &~s(<link rel="modulepreload" href="/assets/#{&1}">))

        # Preload the latin body font so text paints in the brand face on first render.
        fonts =
          (entry["assets"] || [])
          |> Enum.filter(&String.contains?(&1, "latin-wght-normal"))
          |> Enum.map_join(
            "\n",
            &~s(<link rel="preload" href="/assets/#{&1}" as="font" type="font/woff2" crossorigin>)
          )

        """
        #{fonts}
        #{css}
        #{preloads}
        <script type="module" src="/assets/#{entry["file"]}"></script>
        """
    end
  end

  # Every chunk the entry imports statically, each once, dependencies before the chunks
  # that import them (the order Vite itself writes CSS in). Dynamic imports are left out:
  # they load their own CSS when they run.
  @doc false
  def imported_chunks(manifest, key) do
    {chunks, _seen} = collect(manifest, manifest[key]["imports"] || [], {[], %{key => true}})
    Enum.reverse(chunks)
  end

  defp collect(manifest, keys, acc) do
    Enum.reduce(keys, acc, fn key, {chunks, seen} = acc ->
      case manifest[key] do
        chunk when is_map(chunk) and not is_map_key(seen, key) ->
          {chunks, seen} =
            collect(manifest, chunk["imports"] || [], {chunks, Map.put(seen, key, true)})

          {[chunk | chunks], seen}

        _ ->
          acc
      end
    end)
  end
end
