defmodule StarterKit.DataCase do
  @moduledoc "Tests that touch the database (SQL sandbox)."

  use Boundary, top_level?: true, check: [in: false, out: false]

  use ExUnit.CaseTemplate

  using do
    quote do
      alias StarterKit.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import StarterKit.DataCase
      import StarterKit.Fixtures
      import StarterKit.FlagHelpers
    end
  end

  setup tags do
    StarterKit.DataCase.setup_sandbox(tags)
    :ok
  end

  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(StarterKit.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end

  @doc "Changeset errors as `%{field => [message]}` (untranslated)."
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
