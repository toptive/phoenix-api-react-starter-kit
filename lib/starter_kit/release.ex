defmodule StarterKit.Release do
  @moduledoc """
  Release tasks (no Mix in production). `bin/launch` (the Kamal container command)
  runs `bin/migrate` at boot, before the server:

      bin/starter_kit eval "StarterKit.Release.migrate_and_sync()"

  The first superadmin of a new installation (docs/ADMIN.md):

      kamal app exec 'bin/starter_kit eval "StarterKit.Release.bootstrap_admin(\\"you@example.com\\")"'
  """

  use Boundary, top_level?: true, deps: [StarterKit.Repo, StarterKit.I18n, StarterKit.Accounts]

  @app :starter_kit

  @doc "Runs migrations, then syncs the i18n table with the CSV."
  def migrate_and_sync do
    migrate()
    {:ok, _, _} = Ecto.Migrator.with_repo(StarterKit.Repo, fn _ -> i18n_sync() end)
    :ok
  end

  @doc """
  Makes `email` the first superadmin (`StarterKit.Accounts.bootstrap_superadmin/1`).
  Refused when a superadmin already exists. The person then signs in with a magic link.
  """
  def bootstrap_admin(email) when is_binary(email) do
    load_app()

    {:ok, result, _} =
      Ecto.Migrator.with_repo(StarterKit.Repo, fn _ ->
        StarterKit.Accounts.bootstrap_superadmin(email)
      end)

    case result do
      {:ok, user} ->
        IO.puts("Superadmin: #{user.email}. Sign in at /session/new with a magic link.")

      {:error, :already_bootstrapped} ->
        raise "Refused: a superadmin already exists. Promote others in Admin → Users."

      {:error, %Ecto.Changeset{} = changeset} ->
        raise "Refused: #{inspect(changeset.errors)}"
    end
  end

  @doc "Runs pending migrations."
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  @doc "Rolls back `repo` to `version`."
  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp i18n_sync do
    {:ok, _} = Application.ensure_all_started(:phoenix_pubsub)
    Phoenix.PubSub.Supervisor.start_link(name: StarterKit.PubSub)
    IO.puts("i18n sync: #{inspect(StarterKit.I18n.sync())}")
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
