defmodule StarterKit.OtpRuntimeTest do
  @moduledoc """
  "OTP, concurrency and runtime rules" (AGENTS.md), executable. The checks read source
  and config only, so they are deterministic. AST checks see direct calls only: a call
  through a wrapper module is not seen, and the written rule still applies.

  """
  use ExUnit.Case, async: true

  # Connections kept free for web requests, channels and Oban's own queries.
  @web_headroom 4
  @http_clients [:Req, :Finch, :HTTPoison, :Tesla, :Mint]
  @max_lifeline_ms :timer.minutes(15)

  defp lib_sources do
    for path <- Path.wildcard("lib/**/*.ex"), do: {path, Code.string_to_quoted!(File.read!(path))}
  end

  defp find(ast, fun) do
    {_, found} = Macro.prewalk(ast, [], fn node, acc -> {node, fun.(node) ++ acc} end)
    found
  end

  defp remote_call?({{:., _, [{:__aliases__, _, parts}, _fun]}, _, _}, modules),
    do: List.first(parts) in modules or List.last(parts) in modules

  defp remote_call?({{:., _, [:httpc, _fun]}, _, _}, _modules), do: true
  defp remote_call?(_node, _modules), do: false

  defp http_calls(ast),
    do: find(ast, fn node -> if remote_call?(node, @http_clients), do: [node], else: [] end)

  defp line({_, meta, _}), do: meta[:line]

  test "no GenServer.call / :gen_server.call / Task.await with an :infinity timeout" do
    offenders =
      for {path, ast} <- lib_sources(),
          node <- find(ast, fn node -> if infinity_call?(node), do: [node], else: [] end),
          do: "#{path}:#{line(node)}"

    assert offenders == [], "use a finite timeout:\n" <> Enum.join(offenders, "\n")
  end

  defp infinity_call?({{:., _, [mod, fun]}, _, [_ | _] = args}) do
    fun in [:call, :await, :get, :multi_call] and List.last(args) == :infinity and
      (mod == :gen_server or
         match?({:__aliases__, _, [m]} when m in [:GenServer, :Task, :Agent], mod))
  end

  defp infinity_call?(_node), do: false

  test "no HTTP client call inside a Repo transaction" do
    offenders =
      for {path, ast} <- lib_sources(),
          {{:., _, [{:__aliases__, _, parts}, fun]}, _, args} <-
            find(ast, fn
              {{:., _, [{:__aliases__, _, _}, fun]}, _, _} = node
              when fun in [:transact, :transaction] ->
                [node]

              _ ->
                []
            end),
          List.last(parts) == :Repo,
          call <- http_calls(args),
          do: "#{path}:#{line(call)} (Repo.#{fun})"

    assert offenders == [],
           "do the HTTP/LLM call before or after the transaction:\n" <> Enum.join(offenders, "\n")
  end

  test "no HTTP client call inside handle_call/3" do
    offenders =
      for {path, ast} <- lib_sources(),
          clause <-
            find(ast, fn
              {:def, _, [{:handle_call, _, [_, _, _]}, _]} = node -> [node]
              {:def, _, [{:when, _, [{:handle_call, _, [_, _, _]} | _]}, _]} = node -> [node]
              _ -> []
            end),
          call <- http_calls(clause),
          do: "#{path}:#{line(call)}"

    assert offenders == [],
           "run IO in Task.Supervisor.async_nolink or a per-entity process:\n" <>
             Enum.join(offenders, "\n")
  end

  test "ETS tables are created in init/1 of a supervised process" do
    offenders =
      for {path, ast} <- lib_sources(),
          {_, _, [head, _]} = def <-
            find(ast, fn
              {kind, _, [_, _]} = node when kind in [:def, :defp] -> [node]
              _ -> []
            end),
          def_name(head) != :init,
          call <- find(def, fn node -> if ets_new?(node), do: [node], else: [] end),
          do: "#{path}:#{line(call)}"

    assert offenders == [], "create ETS tables in init/1:\n" <> Enum.join(offenders, "\n")
  end

  defp def_name({:when, _, [head | _]}), do: def_name(head)
  defp def_name({name, _, _}), do: name

  defp ets_new?({{:., _, [:ets, :new]}, _, _}), do: true
  defp ets_new?(_node), do: false

  test "the health check uses StarterKit.Health only (no context, no Repo)" do
    source = File.read!("lib/starter_kit_web/controllers/health_controller.ex")
    refute source =~ ~r/Repo\.|StarterKit\.(?!Health\b)[A-Z]\w*\./
  end

  describe "Oban" do
    @describetag :config
    defp oban(env),
      do: "config/config.exs" |> Config.Reader.read!(env: env) |> get_in([:starter_kit, Oban])

    test "Pruner and Lifeline are enabled" do
      plugins =
        Enum.map(oban(:dev)[:plugins], fn
          {mod, _} -> mod
          mod -> mod
        end)

      assert Oban.Plugins.Pruner in plugins
      assert Oban.Plugins.Lifeline in plugins
    end

    test "Lifeline rescues orphaned jobs within 15 minutes" do
      opts =
        Enum.find_value(oban(:dev)[:plugins], [], fn
          {Oban.Plugins.Lifeline, opts} -> opts
          _ -> nil
        end)

      assert opts[:rescue_after] && opts[:rescue_after] <= @max_lifeline_ms
    end

    test "dev: queue concurrency + web headroom fits in the Repo pool" do
      config = Config.Reader.read!("config/config.exs", env: :dev)
      pool = get_in(config, [:starter_kit, StarterKit.Repo, :pool_size])
      slots = config |> get_in([:starter_kit, Oban, :queues]) |> Keyword.values() |> Enum.sum()

      assert slots + @web_headroom <= pool,
             "queues use #{slots} slots + #{@web_headroom} headroom > pool_size #{pool}"
    end

    test "prod (deploy.yml, else runtime.exs defaults): queues + web headroom fit in the pool" do
      deploy = if File.exists?("config/deploy.yml"), do: File.read!("config/deploy.yml"), else: ""

      deployed = fn name ->
        Regex.run(~r/^\s*#{name}:\s*"?(\d+)/m, deploy, capture: :all_but_first)
      end

      source = File.read!("config/runtime.exs")

      [default_pool] =
        Regex.run(~r/env\.\("POOL_SIZE"\)\s*\|\|\s*"(\d+)"/, source, capture: :all_but_first)

      [pool] = deployed.("POOL_SIZE") || [default_pool]

      slots =
        ~r/env\.\("(OBAN_\w+_CONCURRENCY)"\)\s*\|\|\s*"(\d+)"/
        |> Regex.scan(source, capture: :all_but_first)
        |> Enum.map(fn [name, n] -> String.to_integer(hd(deployed.(name) || [n])) end)
        |> Enum.sum()

      assert slots + @web_headroom <= String.to_integer(pool),
             "prod queues use #{slots} slots + #{@web_headroom} headroom > POOL_SIZE #{pool}"
    end

    test "every Oban worker sets timeout/1" do
      offenders =
        for path <- Path.wildcard("lib/**/*.ex"),
            source = File.read!(path),
            source =~ "use Oban.Worker",
            not (source =~ ~r/def timeout\(/),
            do: path

      assert offenders == [],
             "add `def timeout(_job), do: :timer.minutes(n)`: #{inspect(offenders)}"
    end
  end

  test "dev: logger level is :info or higher and Repo query logging is off by default" do
    config = Config.Reader.read!("config/config.exs", env: :dev)
    assert Logger.compare_levels(get_in(config, [:logger, :level]) || :debug, :info) != :lt
    assert get_in(config, [:starter_kit, StarterKit.Repo, :log]) == false
  end
end
