defmodule StarterKit.Accounts.UserPolicy do
  @moduledoc "Who may see and change users. Only superadmins manage other users."

  @behaviour StarterKit.Policy

  import Ecto.Query

  alias StarterKit.Accounts.{Scope, User}

  @impl true
  def authorize(%Scope{user: %User{id: id}}, action, %User{id: id})
      when action in [:show, :edit, :update, :delete],
      do: true

  def authorize(%Scope{} = scope, action, _user)
      when action in [:index, :show, :edit, :update, :impersonate],
      do: Scope.superadmin?(scope)

  def authorize(_scope, _action, _resource), do: false

  @impl true
  def scope(%Scope{} = scope, queryable) do
    if Scope.superadmin?(scope),
      do: queryable,
      else: where(queryable, [u], u.id == ^scope.user.id)
  end
end
