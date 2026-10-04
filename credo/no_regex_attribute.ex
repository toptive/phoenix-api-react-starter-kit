defmodule StarterKit.Credo.NoRegexAttribute do
  @moduledoc """
  No compiled regex in a module attribute. On OTP 28 a regex built at compile time and
  kept in `@name` is recompiled on every use (whvisas: a 10 s batch became 0.6 s).
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Keep the pattern source in the attribute (or inline the `~r` in the function) and
      compile it once at runtime, cached in `:persistent_term`. See docs/PERFORMANCE.md.
      """
    ]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  defp traverse({:@, meta, [{name, _, [value]}]} = ast, issues, issue_meta) when is_atom(name) do
    if regex?(value),
      do: {ast, [issue_for(issue_meta, meta[:line], name) | issues]},
      else: {ast, issues}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp regex?(value) do
    {_, found} =
      Macro.prewalk(value, false, fn
        {:sigil_r, _, _} = node, _acc ->
          {node, true}

        {{:., _, [{:__aliases__, _, [:Regex]}, fun]}, _, _} = node, _acc
        when fun in [:compile, :compile!] ->
          {node, true}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp issue_for(issue_meta, line, name) do
    format_issue(issue_meta,
      message: "`@#{name}` holds a compiled regex; OTP 28 recompiles it on every use.",
      trigger: "@#{name}",
      line_no: line
    )
  end
end
