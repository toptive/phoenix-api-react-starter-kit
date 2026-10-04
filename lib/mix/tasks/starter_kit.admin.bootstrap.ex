defmodule Mix.Tasks.StarterKit.Admin.Bootstrap do
  @moduledoc """
  Makes an email the first superadmin of this installation (dev, staging, a fresh
  product). It promotes the existing account or creates a confirmed one without a
  password; the person signs in with a magic link or Google.

      mix starter_kit.admin.bootstrap you@example.com

  Refused once any superadmin exists. In production there is no Mix: use
  `StarterKit.Release.bootstrap_admin/1` (docs/ADMIN.md).
  """
  @shortdoc "Creates the first superadmin"

  use Mix.Task
  use Boundary, top_level?: true, deps: [StarterKit.Accounts]

  @requirements ["app.start"]

  @impl true
  def run([email]) do
    case StarterKit.Accounts.bootstrap_superadmin(email) do
      {:ok, user} ->
        Mix.shell().info("Superadmin: #{user.email}. Sign in at /session/new with a magic link.")

      {:error, :already_bootstrapped} ->
        Mix.raise("Refused: a superadmin already exists. Promote others in Admin → Users.")

      {:error, %Ecto.Changeset{} = changeset} ->
        Mix.raise("Refused: #{inspect(changeset.errors)}")
    end
  end

  def run(_args), do: Mix.raise("Usage: mix starter_kit.admin.bootstrap EMAIL")
end
