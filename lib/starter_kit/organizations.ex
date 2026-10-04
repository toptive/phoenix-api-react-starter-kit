defmodule StarterKit.Organizations do
  @moduledoc """
  Tenancy: organizations, memberships and invitations.

  Mode (`config :starter_kit, :tenancy`):

    * `:multi` (default) — a new user gets a personal organization; people join others
      through invitations and switch between them;
    * `:single` — one shared organization (`"default"` slug); every user joins it as a
      member. The model stays the same, the UI hides organization switching.
  """

  use Boundary,
    top_level?: true,
    deps: [
      StarterKit.Repo,
      StarterKit.Schema,
      StarterKit.Policy,
      StarterKit.Accounts,
      StarterKit.Audit,
      StarterKit.Notifications,
      StarterKit.I18n,
      StarterKit.Flags,
      StarterKit.AbuseProtection
    ],
    exports: [
      Organization,
      Membership,
      Invitation,
      OrganizationPolicy,
      MembershipPolicy,
      InvitationPolicy
    ]

  import Ecto.Query

  alias StarterKit.{Accounts, Audit, Notifications, Repo}
  alias StarterKit.Accounts.{Scope, User}

  alias StarterKit.Organizations.{
    Invitation,
    InvitationPolicy,
    Membership,
    MembershipPolicy,
    Organization,
    OrganizationPolicy
  }

  @doc "`:multi` or `:single`."
  def mode, do: Application.get_env(:starter_kit, :tenancy, :multi)

  ## Current organization

  @doc """
  Builds the scope for a signed-in user: picks `preferred_id` when the user is a member,
  else the last used organization, else the first membership. Creates the personal
  organization (multi mode) or joins the default organization (single mode) when the
  user has none.
  """
  def scope_for(%Scope{user: %User{} = user} = scope, preferred_id \\ nil) do
    memberships = memberships_of(user)

    memberships =
      if memberships == [] do
        {:ok, _} = ensure_membership(user)
        memberships_of(user)
      else
        memberships
      end

    membership =
      Enum.find(memberships, &(&1.organization_id == preferred_id)) ||
        Enum.find(memberships, &(&1.organization_id == user.last_organization_id)) ||
        hd(memberships)

    Scope.put_organization(scope, membership.organization, membership)
  end

  defp memberships_of(user) do
    Repo.all(
      from(m in Membership,
        where: m.user_id == ^user.id,
        join: o in assoc(m, :organization),
        order_by: [asc: o.name],
        preload: [organization: o]
      ),
      skip_org_id: true
    )
  end

  defp ensure_membership(user) do
    case mode() do
      :single -> join_default_organization(user)
      _ -> create_personal_organization(user)
    end
  end

  defp create_personal_organization(user) do
    name = if user.name in [nil, ""], do: user.email, else: user.name

    name = String.slice(if(String.length(name) < 2, do: user.email, else: name), 0, 80)
    create_organization(user, %{name: name}, personal: true)
  end

  defp join_default_organization(user) do
    Repo.insert!(%Organization{name: "Default", slug: "default"},
      on_conflict: :nothing,
      conflict_target: :slug
    )

    org = Repo.get_by!(Organization, slug: "default")

    role =
      if Repo.exists?(from(m in Membership), org_id: org.id), do: :member, else: :owner

    Repo.insert(%Membership{organization_id: org.id, user_id: user.id, role: role},
      on_conflict: :nothing
    )
  end

  @doc "The organizations the scope's user belongs to (for the switcher)."
  def list_user_organizations(%Scope{user: user}) do
    Repo.all(
      from(o in Organization,
        join: m in Membership,
        on: m.organization_id == o.id and m.user_id == ^user.id,
        order_by: o.name
      ),
      skip_org_id: true
    )
  end

  @doc "Switches the current organization. Returns the new scope, or `{:error, :not_member}`."
  def switch_organization(%Scope{user: user} = scope, organization_id) do
    case Repo.get_by(Membership, [user_id: user.id, organization_id: organization_id],
           skip_org_id: true
         ) do
      nil ->
        {:error, :not_member}

      %Membership{} ->
        {:ok, _} = Accounts.remember_organization(user, organization_id)
        {:ok, scope_for(scope, organization_id)}
    end
  end

  ## Organizations

  @doc """
  Creates an organization owned by `user` (one transaction: organization + owner
  membership + audit event). Options: `personal: true`, `onboarded: true` (skip the
  onboarding steps).
  """
  def create_organization(%User{} = user, attrs, opts \\ []) do
    onboarded_at = if opts[:onboarded], do: DateTime.utc_now(:second)

    changeset =
      Organization.create_changeset(
        %Organization{personal: opts[:personal] || false, onboarded_at: onboarded_at},
        attrs
      )

    Repo.transact(fn ->
      with {:ok, org} <- Repo.insert(changeset),
           {:ok, membership} <- Repo.insert(owner_membership(org, user)) do
        Audit.record("organization.created", actor: user, subject: org, organization_id: org.id)
        {:ok, %{membership | organization: org}}
      end
    end)
  end

  defp owner_membership(org, user),
    do: %Membership{organization_id: org.id, user_id: user.id, role: :owner, access: :full}

  @doc """
  Creates another organization for the scope's user and returns it. The form already
  asked for its name, so it starts onboarded.
  """
  def create_user_organization(%Scope{user: user}, attrs) do
    with {:ok, membership} <- create_organization(user, attrs, onboarded: true) do
      {:ok, _} = Accounts.remember_organization(user, membership.organization_id)
      {:ok, membership.organization}
    end
  end

  @doc "A changeset for organization forms."
  def change_organization(organization \\ %Organization{}, attrs \\ %{}),
    do: Organization.changeset(organization, attrs)

  @doc "Gets an organization the scope may see (member or superadmin)."
  def get_organization!(%Scope{} = scope, id) do
    if Scope.superadmin?(scope) or Scope.organization_id(scope) == id do
      Repo.get!(Organization, id)
    else
      raise Ecto.NoResultsError, queryable: Organization
    end
  end

  @doc "Renames the organization (audited)."
  def update_organization(%Scope{} = scope, %Organization{} = org, attrs) do
    changeset = Organization.changeset(org, attrs)
    Repo.transact(fn -> save_organization(scope, changeset, "organization.updated") end)
  end

  @doc "Number of organizations (admin dashboard)."
  def count_organizations, do: Repo.aggregate(Organization, :count)

  @doc "Admin list of all organizations with member counts."
  def list_organizations(%Scope{} = _scope, params) do
    search = params |> Map.get("q", "") |> String.trim()

    query =
      from(o in Organization,
        left_join: m in Membership,
        on: m.organization_id == o.id,
        group_by: o.id,
        order_by: [desc: o.inserted_at],
        select: %{organization: o, members: count(m.id)}
      )

    query = if search == "", do: query, else: where(query, [o], ilike(o.name, ^"%#{search}%"))
    Repo.paginate(query, params, skip_org_id: true)
  end

  ## Memberships

  @doc "Members of the current organization, with their users."
  def list_memberships(%Scope{} = scope) do
    Repo.all(
      from(m in Membership,
        join: u in assoc(m, :user),
        order_by: [asc: m.inserted_at, asc: m.id],
        preload: [user: u]
      ),
      org_id: Scope.organization_id(scope)
    )
  end

  @doc "Memberships of any organization (admin area)."
  def list_organization_memberships(%Organization{id: org_id}) do
    Repo.all(
      from(m in Membership, join: u in assoc(m, :user), order_by: u.email, preload: [user: u]),
      org_id: org_id
    )
  end

  @doc "Gets a membership of the current organization."
  def get_membership!(%Scope{} = scope, id) do
    Repo.get!(Membership, id, org_id: Scope.organization_id(scope))
  end

  @doc """
  Changes role/access. The last owner cannot be demoted. The organization row is locked
  first, so two owners cannot demote or remove each other at the same time.
  """
  def update_membership(%Scope{} = scope, %Membership{} = membership, attrs) do
    Repo.transact(fn -> change_membership(scope, lock_and_reload(membership), attrs) end)
  end

  defp change_membership(scope, membership, attrs) do
    scope = refresh_membership(scope)
    changeset = Membership.changeset(membership, attrs)

    cond do
      not OrganizationPolicy.manager?(scope) ->
        {:error, :forbidden}

      (membership.role == :owner or Ecto.Changeset.get_field(changeset, :role) == :owner) and
          not Scope.role_in?(scope, [:owner]) ->
        {:error, Ecto.Changeset.add_error(changeset, :role, "validation.owner_only")}

      membership.role == :owner and Ecto.Changeset.get_field(changeset, :role) != :owner and
          last_owner?(membership) ->
        {:error, Ecto.Changeset.add_error(changeset, :role, "validation.last_owner")}

      true ->
        save_membership(scope, changeset)
    end
  end

  defp save_membership(scope, changeset) do
    with {:ok, updated} <- Repo.update(changeset) do
      Audit.record("membership.updated",
        scope: scope,
        subject: updated,
        metadata: %{role: updated.role, access: updated.access}
      )

      {:ok, Repo.preload(updated, :user)}
    end
  end

  @doc "Removes a member (or leaves). The last owner cannot leave (organization locked first)."
  def delete_membership(%Scope{} = scope, %Membership{} = membership) do
    Repo.transact(fn -> remove_membership(scope, lock_and_reload(membership)) end)
  end

  defp remove_membership(scope, membership) do
    scope = refresh_membership(scope)

    cond do
      not MembershipPolicy.authorize(scope, :delete, membership) -> {:error, :forbidden}
      membership.role == :owner and last_owner?(membership) -> {:error, :last_owner}
      true -> delete_audited_membership(scope, membership)
    end
  end

  defp delete_audited_membership(scope, membership) do
    with {:ok, deleted} <- Repo.delete(membership) do
      Audit.record("membership.deleted",
        scope: scope,
        subject: deleted,
        metadata: %{user_id: deleted.user_id}
      )

      {:ok, deleted}
    end
  end

  defp refresh_membership(scope) do
    membership =
      Repo.get_by(Membership, [user_id: scope.user.id], org_id: Scope.organization_id(scope))

    %{scope | membership: membership}
  end

  @doc """
  Locks the organization rows (`FOR UPDATE`, in id order so two callers never deadlock).
  Every change that can remove an owner takes this lock first. Call it inside a transaction.
  """
  def lock_organizations(ids) do
    Repo.all(from(o in Organization, where: o.id in ^ids, order_by: o.id, lock: "FOR UPDATE"))
  end

  # The role read before the lock may be stale: read the membership again under it.
  defp lock_and_reload(%Membership{id: id, organization_id: org_id}) do
    lock_organizations([org_id])
    Repo.get!(Membership, id, org_id: org_id)
  end

  defp last_owner?(%Membership{organization_id: org_id}) do
    Repo.aggregate(from(m in Membership, where: m.role == :owner), :count, org_id: org_id) <= 1
  end

  ## Onboarding

  @doc """
  True when the scope's organization has not finished onboarding and the user manages it.
  Members and an impersonating admin never see onboarding.
  """
  def onboarding_required?(%Scope{organization: %Organization{onboarded_at: nil}} = scope),
    do: is_nil(scope.impersonator) and OrganizationPolicy.manager?(scope)

  def onboarding_required?(_scope), do: false

  @doc """
  Finishes onboarding for the current organization (audited). Each answer is optional:
  a skipped step sends a blank value and keeps what is there.
  """
  def complete_onboarding(%Scope{organization: %Organization{} = org} = scope, attrs) do
    changeset = Organization.onboarding_changeset(org, attrs)
    Repo.transact(fn -> save_organization(scope, changeset, "organization.onboarded") end)
  end

  defp save_organization(scope, changeset, action) do
    with {:ok, updated} <- Repo.update(changeset),
         {:ok, _event} <- Audit.record(action, scope: scope, subject: updated) do
      {:ok, updated}
    end
  end

  ## Invitations

  @doc "A changeset for the invitation form."
  def change_invitation(attrs \\ %{}), do: Invitation.changeset(%Invitation{}, attrs)

  @doc "Pending invitations of the current organization."
  def list_invitations(%Scope{} = scope) do
    Repo.all(
      from(i in Invitation,
        where: is_nil(i.accepted_at) and i.expires_at > ^now(),
        order_by: [desc: i.inserted_at]
      ),
      org_id: Scope.organization_id(scope)
    )
  end

  @doc "Gets a pending invitation of the current organization."
  def get_invitation!(%Scope{} = scope, id) do
    Repo.get!(Invitation, id, org_id: Scope.organization_id(scope))
  end

  @doc """
  Invites `email` to the current organization and emails the link.
  `url_fun` receives the raw token. `{:error, :email_unavailable}` (nothing written)
  when no mail can be sent.
  """
  def create_invitation(%Scope{} = scope, attrs, url_fun, locale \\ nil) do
    org = scope.organization

    changeset =
      %Invitation{organization_id: org.id, invited_by_id: scope.user.id}
      |> Invitation.changeset(attrs)
      |> validate_not_member(org)

    {token, changeset} = Invitation.put_token(changeset)

    with :ok <- if(Notifications.email_available?(), do: :ok, else: {:error, :email_unavailable}),
         {:ok, invitation} <- Repo.transact(fn -> insert_invitation(scope, changeset) end) do
      Notifications.notify(
        %{email: invitation.email, name: "", locale: locale || scope.user.locale},
        :invitation,
        %{url: url_fun.(token), organization: org.name, inviter: scope.user.name}
      )

      {:ok, invitation}
    end
  end

  @doc "Seats already occupied or reserved by pending invitations."
  def invitation_seat_count(scope) do
    org_id = Scope.organization_id(scope)

    Repo.aggregate(Membership, :count, org_id: org_id) +
      Repo.aggregate(
        from(i in Invitation, where: is_nil(i.accepted_at) and i.expires_at > ^now()),
        :count,
        org_id: org_id
      )
  end

  defp insert_invitation(scope, changeset) do
    org_id = Scope.organization_id(scope)

    Repo.delete_all(
      from(i in Invitation,
        where:
          i.email == ^Ecto.Changeset.get_field(changeset, :email) and is_nil(i.accepted_at) and
            i.expires_at <= ^now()
      ),
      org_id: org_id
    )

    with {:ok, invitation} <- Repo.insert(changeset) do
      Audit.record("invitation.created",
        scope: scope,
        subject: invitation,
        metadata: %{email: invitation.email}
      )

      {:ok, invitation}
    end
  end

  defp validate_not_member(changeset, org) do
    email = Ecto.Changeset.get_field(changeset, :email)

    member? =
      email &&
        Repo.exists?(
          from(m in Membership, join: u in assoc(m, :user), where: u.email == ^email),
          org_id: org.id
        )

    if member?,
      do: Ecto.Changeset.add_error(changeset, :email, "validation.already_member"),
      else: changeset
  end

  @doc "Revokes a pending invitation."
  def delete_invitation(%Scope{} = scope, %Invitation{} = invitation) do
    with {:ok, deleted} <- Repo.delete(invitation) do
      Audit.record("invitation.revoked",
        scope: scope,
        subject: deleted,
        metadata: %{email: deleted.email}
      )

      {:ok, deleted}
    end
  end

  @doc """
  Signs up through the registration form: `StarterKit.Accounts.register_user/3` with
  `invited: true` when `attrs["email"]` has an open invitation (what `:invite` mode needs).
  """
  def register_user(attrs, url_fun, opts \\ []) do
    invited = invited_email?(attrs["email"])
    Accounts.register_user(attrs, url_fun, Keyword.put(opts, :invited, invited))
  end

  @doc "The public bootstrap and optional authenticated scope."
  def bootstrap(scope, locale) do
    %{
      auth: auth(scope),
      locale: locale,
      locales: StarterKit.I18n.locales(),
      i18n_version: StarterKit.I18n.version(),
      flags: StarterKit.Flags.public(),
      turnstile: StarterKit.AbuseProtection.widget(),
      app: %{
        name: Application.fetch_env!(:starter_kit, :app_name),
        tenancy: mode(),
        signup_mode: Accounts.signup_mode(),
        google_enabled: Application.get_env(:starter_kit, :google_auth, false),
        email_available: Accounts.email_sign_in_available?(),
        public_url: Application.fetch_env!(:starter_kit, :spa_origin)
      }
    }
  end

  @doc "The authenticated part of bootstrap."
  def auth(nil), do: nil

  def auth(scope) do
    %{
      user: scope.user,
      organization: scope.organization,
      membership: %{scope.membership | user: nil},
      organizations: list_user_organizations(scope),
      superadmin: Scope.superadmin?(scope),
      impersonator: scope.impersonator,
      onboarding_required: onboarding_required?(scope),
      sudo_until: scope.session.sudo_until,
      session_id: scope.session.id
    }
  end

  @doc "Password sign-in with a device-local organization."
  def create_password_session(attrs, device, current) do
    Repo.transact(fn ->
      with {:ok, session} <- Accounts.create_api_session(attrs, device, current),
           do: initialize_session(session)
    end)
  end

  @doc "Magic-link sign-in with a device-local organization."
  def create_link_session(token, device, current) do
    Repo.transact(fn ->
      with {:ok, session} <- Accounts.create_magic_link_session(token, device, current),
           do: initialize_session(session)
    end)
  end

  defp initialize_session(payload) do
    current = payload.user |> Scope.for_user() |> scope_for(payload.session.organization_id)

    with {:ok, _} <- Accounts.set_session_organization(payload.session, current.organization.id) do
      {:ok, payload}
    end
  end

  @doc "Exchanges the provider code, applies signup policy and issues an API session."
  def create_google_api_session(code, redirect_uri, locale, device) do
    with true <- is_binary(code) || {:error, :oauth_failed},
         {:ok, info} <- Accounts.google_identity(code, redirect_uri, locale) do
      Repo.transact(fn -> persist_google_session(info, device) end)
    end
  end

  defp persist_google_session(info, device) do
    new_account = not Accounts.google_account_exists?(info)

    with {:ok, user} <- upsert_google_user(info) do
      initialize_session(
        Map.put(Accounts.generate_api_token(user, device), :new_account, new_account)
      )
    end
  end

  @doc "Google sign-in (`StarterKit.Accounts.upsert_google_user/2`), invitation-aware like `register_user/3`."
  def upsert_google_user(info) do
    Accounts.upsert_google_user(info, invited: invited_email?(info[:email]))
  end

  defp invited_email?(email) when is_binary(email) and email != "" do
    Repo.exists?(
      from(i in Invitation,
        where:
          i.email == ^String.trim(email) and is_nil(i.accepted_at) and
            i.expires_at > ^DateTime.utc_now()
      ),
      skip_org_id: true
    )
  end

  defp invited_email?(_email), do: false

  @doc "Finds an open invitation by its raw token (public page), with its organization."
  def get_open_invitation(token) do
    with {:ok, hash} <- Invitation.decode(token),
         %Invitation{} = invitation <-
           Repo.one(
             from(i in Invitation, where: i.token_hash == ^hash, preload: :organization),
             skip_org_id: true
           ),
         true <- Invitation.open?(invitation) do
      {:ok, invitation}
    else
      _ -> {:error, :invitation_invalid}
    end
  end

  @doc """
  Accepts an invitation for the signed-in user. The user's email must match the
  invited email. Returns `{:ok, membership}`.
  """
  def accept_invitation(%Scope{user: user} = scope, token) do
    Repo.transact(fn ->
      with {:ok, invitation} <- get_open_invitation(token),
           invitation <-
             Repo.get!(Invitation, invitation.id,
               org_id: invitation.organization_id,
               lock: "FOR UPDATE"
             ),
           true <- Invitation.open?(invitation) || {:error, :invitation_invalid},
           true <-
             String.downcase(user.email) == String.downcase(invitation.email) ||
               {:error, {:email_mismatch, invitation.email}} do
        join(scope, invitation)
      end
    end)
  end

  defp join(%Scope{user: user} = scope, invitation) do
    with {:ok, _} <- invitation |> Ecto.Changeset.change(accepted_at: now()) |> Repo.update(),
         {:ok, _} <- Repo.insert(membership_from(invitation, user), on_conflict: :nothing),
         {:ok, user} <- Accounts.remember_organization(user, invitation.organization_id),
         :ok <- update_device_org(scope, invitation.organization_id) do
      Audit.record("invitation.accepted",
        scope: scope,
        subject: invitation,
        organization_id: invitation.organization_id
      )

      membership = Repo.get_by!(Membership, [user_id: user.id], org_id: invitation.organization_id)
      {:ok, Repo.preload(membership, :user)}
    end
  end

  defp update_device_org(%Scope{session: nil}, _org_id), do: :ok

  defp update_device_org(scope, org_id) do
    with {:ok, _} <- Accounts.set_session_organization(scope.session, org_id), do: :ok
  end

  @doc "Switches this device and returns the refreshed Auth payload."
  def switch_current_organization(scope, organization_id) do
    case Ecto.UUID.cast(organization_id) do
      {:ok, _} -> Repo.transact(fn -> switch_device(scope, organization_id) end)
      _ -> {:error, :not_member}
    end
  end

  defp switch_device(scope, organization_id) do
    with {:ok, current} <- switch_organization(scope, organization_id),
         :ok <- update_device_org(scope, organization_id) do
      {:ok, auth(current)}
    end
  end

  @doc "Creates an onboarded organization and switches this device atomically."
  def create_current_organization(scope, attrs) do
    if mode() == :multi,
      do: Repo.transact(fn -> create_device_organization(scope, attrs) end),
      else: {:error, :forbidden}
  end

  defp create_device_organization(scope, attrs) do
    with {:ok, org} <- create_user_organization(scope, attrs),
         :ok <- update_device_org(scope, org.id) do
      {:ok, org}
    end
  end

  @doc "The current organization's onboarding questions and completion state."
  def onboarding(scope),
    do: %{
      organization_name: scope.organization.name,
      required: is_nil(scope.organization.onboarded_at)
    }

  @doc "Organization settings and whether this member can edit them."
  def organization_settings(scope),
    do: %{organization: scope.organization, can_edit: OrganizationPolicy.manager?(scope)}

  @doc "Public invitation preview, optionally personalized by a bearer."
  def invitation_preview(scope, token) do
    with {:ok, invitation} <- get_open_invitation(token) do
      {:ok,
       %{
         organization: invitation.organization.name,
         email: invitation.email,
         role: invitation.role,
         access: invitation.access,
         expires_at: invitation.expires_at,
         email_matches:
           not is_nil(scope) and
             String.downcase(scope.user.email) == String.downcase(invitation.email)
       }}
    end
  end

  @doc "Changes a member through the scoped API, retaining owner-only validation."
  def update_member(scope, id, attrs) do
    with {:ok, membership} <- find_tenant_record(scope, Membership, id),
         true <- OrganizationPolicy.manager?(scope) || {:error, :forbidden} do
      update_membership(scope, membership, attrs)
    end
  end

  @doc "Removes a member or leaves, resetting the leaving device's organization."
  def remove_member(scope, id) do
    Repo.transact(fn ->
      with {:ok, membership} <- find_tenant_record(scope, Membership, id),
           true <- MembershipPolicy.authorize(scope, :delete, membership) || {:error, :forbidden},
           {:ok, deleted} <- delete_membership(scope, membership) do
        reset_leaving_device(scope, membership)

        {:ok, deleted}
      end
    end)
  end

  defp reset_leaving_device(scope, %{user_id: id}) when id == scope.user.id do
    current = scope_for(scope)
    {:ok, _} = Accounts.remember_organization(scope.user, current.organization.id)
    update_device_org(scope, current.organization.id)
  end

  defp reset_leaving_device(_scope, _membership), do: :ok

  @doc "Revokes an invitation from this tenant only."
  def revoke_invitation(scope, id) do
    with {:ok, invitation} <- find_tenant_record(scope, Invitation, id),
         true <- InvitationPolicy.authorize(scope, :delete, invitation) || {:error, :forbidden} do
      delete_invitation(scope, invitation)
    end
  end

  defp find_tenant_record(scope, schema, id) do
    with {:ok, _} <- Ecto.UUID.cast(id),
         record when not is_nil(record) <-
           Repo.get(schema, id, org_id: Scope.organization_id(scope)) do
      {:ok, record}
    else
      _ -> {:error, :not_found}
    end
  end

  defp membership_from(invitation, user) do
    %Membership{
      organization_id: invitation.organization_id,
      user_id: user.id,
      role: invitation.role,
      access: invitation.access
    }
  end

  defp now, do: DateTime.utc_now(:second)
end
