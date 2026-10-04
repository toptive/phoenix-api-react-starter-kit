defmodule StarterKit.Policy do
  @moduledoc """
  The Pundit equivalent. One policy module per schema:

      defmodule StarterKit.Organizations.OrganizationPolicy do
        @behaviour StarterKit.Policy

        @impl true
        def authorize(scope, :update, %Organization{} = org), do: Scope.role_in?(scope, org, [:owner, :admin])
        def authorize(_scope, _action, _resource), do: false

        @impl true
        def scope(scope, queryable), do: …
      end

  Controllers call `StarterKitWeb.Authorization.authorize!/3`, which resolves the policy
  from the resource (a struct or a schema module) and calls `authorize/3`.
  Unknown actions MUST return `false` (deny by default).
  """

  use Boundary, top_level?: true, deps: [], exports: []

  @type scope :: struct() | nil
  @type action :: atom()
  @type resource :: struct() | module()

  @callback authorize(scope(), action(), resource()) :: boolean()
  @callback scope(scope(), Ecto.Queryable.t()) :: Ecto.Queryable.t()
  @optional_callbacks scope: 2

  @doc "Returns true when `scope` may perform `action` on `resource`."
  @spec allowed?(scope(), action(), resource()) :: boolean()
  def allowed?(scope, action, resource) do
    policy_for!(resource).authorize(scope, action, resource) == true
  end

  @doc "Narrows `queryable` to the rows `scope` may see."
  @spec scope(scope(), module()) :: Ecto.Queryable.t()
  def scope(scope, schema) when is_atom(schema), do: policy_for!(schema).scope(scope, schema)

  @doc "The policy module declared by the resource's schema."
  @spec policy_for!(resource()) :: module()
  def policy_for!(%module{}), do: policy_for!(module)

  def policy_for!(module) when is_atom(module) do
    Code.ensure_loaded(module)

    if function_exported?(module, :__policy__, 0) and module.__policy__() do
      module.__policy__()
    else
      raise ArgumentError,
            "#{inspect(module)} declares no policy (use StarterKit.Schema, policy: …)"
    end
  end
end
