defmodule StarterKit.Privacy do
  @moduledoc """
  Personal data: account deletion.

  Deleting an account never leaves an organization without an owner and never deletes a
  workspace that Stripe can still charge:

    * an owner of an organization with other people must make one of them an owner
      first (`:transfer_ownership`);
    * the only person in an organization with an open subscription must cancel it first
      (`:subscription_active`);
    * an organization left with nobody in it is deleted with its data (FK cascade), unless
      it has billing history, which stays as a record.

  The organizations are locked (`Organizations.lock_organizations/1`) before the checks,
  so a membership change cannot race the deletion.
  """

  use Boundary,
    top_level?: true,
    deps: [
      StarterKit.Repo,
      StarterKit.Accounts,
      StarterKit.Organizations,
      StarterKit.Billing,
      StarterKit.Audit
    ]

  import Ecto.Query

  alias StarterKit.{Accounts, Audit, Billing, Organizations, Repo}
  alias StarterKit.Accounts.{Scope, User}
  alias StarterKit.Organizations.Membership

  @doc """
  What stops the scope's user from deleting the account: `nil`, or
  `{:transfer_ownership | :subscription_active, organization}` (the first one found).
  """
  def deletion_blocker(%Scope{user: %User{id: user_id}}) do
    user_id |> memberships_of() |> Enum.find_value(&blocker(&1, user_id))
  end

  @doc "Account deletion preview for the settings API."
  def account_deletion(scope) do
    blocker =
      case deletion_blocker(scope) do
        {reason, organization} -> %{reason: reason, organization: organization.name}
        nil -> nil
      end

    %{blocker: blocker}
  end

  @doc """
  Deletes the scope's user (`Accounts.delete_user/1`) and the organizations left empty.
  `{:error, {reason, organization_name}}` when `deletion_blocker/1` finds a
  reason; nothing is written then.
  """
  def delete_account(%Scope{user: %User{id: user_id}} = scope) do
    Repo.transact(fn ->
      memberships = memberships_of(user_id)
      memberships |> Enum.map(& &1.organization_id) |> Organizations.lock_organizations()
      # Read again under the lock: a membership may have changed while we waited.
      memberships = memberships_of(user_id)

      case Enum.find_value(memberships, &blocker(&1, user_id)) do
        {reason, organization} ->
          {:error, {reason, organization.name}}

        nil ->
          delete_with_orphans(scope, memberships)
      end
    end)
  end

  defp delete_with_orphans(%Scope{user: user} = scope, memberships) do
    orphans = memberships |> Enum.reject(&others?(&1, user.id)) |> Enum.map(& &1.organization)
    {:ok, deleted} = Accounts.delete_user(scope)
    Enum.each(orphans, &delete_orphan(&1, user))
    {:ok, deleted}
  end

  defp memberships_of(user_id) do
    Repo.all(from(m in Membership, where: m.user_id == ^user_id, preload: :organization),
      skip_org_id: true
    )
  end

  defp blocker(%Membership{organization: org} = membership, user_id) do
    cond do
      not others?(membership, user_id) ->
        if Billing.subscription_state(org.id) == :open, do: {:subscription_active, org}

      membership.role == :owner and not other_owner?(membership, user_id) ->
        {:transfer_ownership, org}

      true ->
        nil
    end
  end

  defp others?(%Membership{organization_id: org_id}, user_id),
    do: Repo.exists?(from(m in Membership, where: m.user_id != ^user_id), org_id: org_id)

  defp other_owner?(%Membership{organization_id: org_id}, user_id) do
    Repo.exists?(from(m in Membership, where: m.user_id != ^user_id and m.role == :owner),
      org_id: org_id
    )
  end

  defp delete_orphan(organization, user) do
    if Billing.subscription_state(organization.id) == :none do
      Repo.delete!(organization)

      Audit.record("organization.deleted",
        actor: user,
        subject: organization,
        organization_id: organization.id
      )
    end
  end
end
