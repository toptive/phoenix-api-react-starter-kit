defmodule StarterKit.Schema do
  @moduledoc """
  `use StarterKit.Schema` in every Ecto schema.

  Sets UUID primary/foreign keys and UTC timestamps, and records:

    * `policy:` — the policy module that authorizes this schema (Pundit-style);
    * `tenant: true` — the table has `organization_id` and every query must be scoped
      (enforced by `StarterKit.Repo.prepare_query/3`).
  """

  use Boundary, top_level?: true, deps: [], exports: []

  defmacro __using__(opts) do
    policy = Keyword.get(opts, :policy)
    tenant = Keyword.get(opts, :tenant, false)

    quote do
      use Ecto.Schema
      import Ecto.Changeset

      @primary_key {:id, :binary_id, autogenerate: true}
      @foreign_key_type :binary_id
      @timestamps_opts [type: :utc_datetime]

      @type t :: %__MODULE__{}

      @doc false
      def __policy__, do: unquote(policy)

      @doc false
      def __tenant__, do: unquote(tenant)
    end
  end
end
