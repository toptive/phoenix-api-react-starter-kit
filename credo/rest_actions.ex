defmodule StarterKit.Credo.RestActions do
  @moduledoc """
  Controllers expose REST actions only: index show new create edit update delete.
  Any other verb is a nested resource controller (`TaskCloneController.create`).
  """

  use Credo.Check,
    base_priority: :high,
    category: :design,
    param_defaults: [actions: ~w(index show new create edit update delete action)a],
    explanations: [
      check: """
      A public function in a controller must be a REST action. Model any other
      verb as a resource: `POST /tasks/:task_id/clone` → `TaskCloneController.create`.
      See docs/ARCHITECTURE.md §2.
      """
    ]

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params) do
    if String.match?(filename, ~r{lib/[a-z_]+_web/controllers/.+_controller\.ex$}) do
      actions = Params.get(params, :actions, __MODULE__)
      issue_meta = IssueMeta.for(source_file, params)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, actions, issue_meta))
    else
      []
    end
  end

  defp traverse({:def, meta, [{name, _, args} | _]} = ast, issues, actions, issue_meta)
       when is_atom(name) and is_list(args) do
    if length(args) == 2 and name not in actions do
      {ast, [issue_for(issue_meta, meta[:line], name) | issues]}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _actions, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, line, name) do
    format_issue(issue_meta,
      message: "`#{name}/2` is not a REST action. Use a nested resource controller.",
      trigger: "#{name}",
      line_no: line
    )
  end
end
