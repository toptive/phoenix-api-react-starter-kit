defmodule StarterKit.ArchitectureTest do
  @moduledoc """
  The rules of AGENTS.md, executable (the Archspec equivalent). `boundary` already fails
  the build when web code touches Repo or a context's private modules; these tests
  cover what the compiler cannot see. Fix the code, never the rule.
  """
  use ExUnit.Case, async: true

  @rest ~w(index show new create edit update delete)a

  defp sources(glob), do: Path.wildcard(glob) |> Enum.map(&{&1, File.read!(&1)})

  defp controller_actions do
    for {path, source} <- sources("lib/starter_kit_web/controllers/**/*_controller.ex"),
        {:def, _, [{name, _, args}, body]} <- defs(source),
        name in @rest and length(args || []) == 2,
        do: {path, name, body}
  end

  defp defs(source) do
    {:ok, ast} = Code.string_to_quoted(source)

    {_, defs} =
      Macro.prewalk(ast, [], fn
        {:def, _, [{:when, _, [head | _]}, body]} = node, acc ->
          {node, [{:def, [], [head, body]} | acc]}

        {:def, _, [_head, _body]} = node, acc ->
          {node, [node | acc]}

        node, acc ->
          {node, acc}
      end)

    defs
  end

  defp calls?(ast, names) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        {name, _, _} = node, _acc when is_atom(name) -> {node, name in names or false}
        node, acc -> {node, acc}
      end)

    found or ast |> Macro.to_string() |> String.contains?(Enum.map(names, &Atom.to_string/1))
  end

  test "every controller action authorizes (authorize!/3) or opts out (skip_authorization/1)" do
    offenders =
      for {path, name, body} <- controller_actions(),
          not calls?(body, [:authorize!, :skip_authorization, :authorize_create]),
          do: "#{path} #{name}/2"

    assert offenders == [], "missing authorization:\n" <> Enum.join(offenders, "\n")
  end

  test "no services/, poros/, errors/ or forms/ directories" do
    forbidden =
      for dir <- Path.wildcard("lib/**/"),
          Path.basename(dir) in ~w(services poros errors forms),
          do: dir

    assert forbidden == []
  end

  test "raw json/2 only in the envelope module" do
    offenders =
      for {path, source} <- sources("lib/starter_kit_web/**/*.ex"),
          path != "lib/starter_kit_web/responses.ex",
          source =~ ~r/(^|[\s|(])json\(/m,
          do: path

    assert offenders == [],
           "render JSON with render_data/3 or render_error/4: #{inspect(offenders)}"
  end

  test "Oban uses the default and marketing queues only" do
    queues = Application.fetch_env!(:starter_kit, Oban)[:queues] |> Keyword.keys() |> Enum.sort()
    assert queues == [:default, :marketing]

    for {path, source} <- sources("lib/**/*.ex"), source =~ "use Oban.Worker" do
      [_, queue] = Regex.run(~r/queue: :(\w+)/, source) || [nil, "default"]
      assert queue in ~w(default marketing), "#{path} uses queue #{queue}"
    end
  end

  test "every tenant schema has an isolation test" do
    tenancy_test = File.read!("test/starter_kit/tenancy_test.exs")

    for {path, source} <- sources("lib/starter_kit/**/*.ex"),
        source =~ ~r/^\s+use StarterKit\.Schema,[^\n]*tenant: true/m do
      [_, module] = Regex.run(~r/defmodule ([\w.]+) do/, source)
      short = module |> String.split(".") |> List.last()

      assert tenancy_test =~ short,
             "#{path}: add an isolation case for #{short} to test/starter_kit/tenancy_test.exs"
    end
  end

  test "controllers and plugs never talk to the database or build changesets" do
    offenders =
      for {path, source} <- sources("lib/starter_kit_web/**/*.ex"),
          source =~
            ~r/\bRepo\.(all|get|get!|get_by|one|insert|update|delete|aggregate|exists\?|transact|preload)\b|Ecto\.Changeset\.(change|cast)|import Ecto\.Query/,
          do: path

    assert offenders == []
  end
end
