defmodule StarterKit.Health do
  @moduledoc "Readiness for the load balancer: the database answers."

  use Boundary, top_level?: true, deps: [StarterKit.Repo], exports: []

  @doc "`:ok` when Postgres answers `SELECT 1`."
  def check do
    repo = Application.get_env(:starter_kit, __MODULE__, [])[:repo] || StarterKit.Repo

    case repo.query("SELECT 1", [], timeout: 2_000) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  rescue
    error -> {:error, error}
  end
end
