defmodule StarterKit.Credo.WorkerPerform do
  @moduledoc """
  An Oban worker's `perform/1` is ONE call to a context function. Logic lives in the
  context, never in the worker.
  """

  use Credo.Check,
    base_priority: :high,
    category: :design,
    explanations: [
      check: """
      `perform/1` must be a single remote call, for example
      `def perform(%Oban.Job{args: %{"id" => id}}), do: Accounts.deliver_welcome(id)`.
      See docs/ARCHITECTURE.md §5.
      """
    ]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    source = SourceFile.source(source_file)

    if String.contains?(source, "use Oban.Worker") do
      issue_meta = IssueMeta.for(source_file, params)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    else
      []
    end
  end

  defp traverse({:def, meta, [{:perform, _, [_]}, body]} = ast, issues, issue_meta) do
    if single_remote_call?(body),
      do: {ast, issues},
      else: {ast, [issue_for(issue_meta, meta[:line]) | issues]}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp single_remote_call?(do: {{:., _, [{:__aliases__, _, _}, fun]}, _, _args}) when is_atom(fun),
    do: true

  defp single_remote_call?(_), do: false

  defp issue_for(issue_meta, line) do
    format_issue(issue_meta,
      message: "perform/1 must be one call to a context function.",
      trigger: "perform",
      line_no: line
    )
  end
end
