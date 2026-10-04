defmodule StarterKit.Accounts.Scope do
  @moduledoc """
  Who is calling, and in which organization. Every context function that reads or
  writes tenant data takes a `%Scope{}` first.

    * `user` — the signed-in `%User{}` (nil for anonymous callers);
    * `organization` / `membership` — the current tenant and the user's membership in it;
    * `impersonator` — the superadmin behind an impersonated session, if any.
  """

  alias StarterKit.Accounts.User

  defstruct user: nil, organization: nil, membership: nil, impersonator: nil

  @type t :: %__MODULE__{
          user: User.t() | nil,
          organization: struct() | nil,
          membership: struct() | nil,
          impersonator: User.t() | nil
        }

  @doc "Creates a scope for the given user (nil for no user)."
  def for_user(%User{} = user), do: %__MODULE__{user: user}
  def for_user(nil), do: nil

  @doc "Adds the current organization and membership."
  def put_organization(%__MODULE__{} = scope, organization, membership) do
    %{scope | organization: organization, membership: membership}
  end

  @doc "Marks the scope as an impersonated session."
  def put_impersonator(%__MODULE__{} = scope, %User{} = admin), do: %{scope | impersonator: admin}
  def put_impersonator(scope, nil), do: scope

  @doc "True for a global superadmin (never true while impersonating someone else)."
  def superadmin?(%__MODULE__{user: %User{role: :superadmin}}), do: true
  def superadmin?(_), do: false

  @doc "The current organization id (nil outside a tenant)."
  def organization_id(%__MODULE__{organization: %{id: id}}), do: id
  def organization_id(_), do: nil

  @doc "True when the membership in the current organization has one of `roles`."
  def role_in?(%__MODULE__{membership: %{role: role}}, roles), do: role in roles
  def role_in?(_, _), do: false

  @doc "True when the membership may change data (access `:full`)."
  def full_access?(%__MODULE__{membership: %{access: :full}}), do: true
  def full_access?(_), do: false
end
