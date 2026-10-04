defmodule StarterKit.Accounts do
  @moduledoc """
  Users, sign-in (magic link, password, Google), sessions and impersonation.

  Registration asks for name + email only. The user confirms the email by clicking a
  magic link, which also signs them in; a password is optional (settings).
  """

  use Boundary,
    top_level?: true,
    deps: [
      StarterKit.Repo,
      StarterKit.Schema,
      StarterKit.Policy,
      StarterKit.Audit,
      StarterKit.Legal,
      StarterKit.Notifications
    ],
    exports: [User, UserToken, Scope, UserPolicy, Impersonation]

  import Ecto.Query, warn: false

  alias StarterKit.Accounts.{Impersonation, Scope, User, UserPolicy, UserToken}
  alias StarterKit.{Audit, Legal, Notifications, Repo}

  ## Getters

  @doc "Gets a user by email."
  def get_user_by_email(email) when is_binary(email), do: Repo.get_by(User, email: email)

  @doc "Gets a user by email and password (nil when either is wrong)."
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc "Gets a user. Raises `Ecto.NoResultsError` when missing."
  def get_user!(id), do: Repo.get!(User, id)

  @doc "Gets a user visible to `scope` (superadmins see all)."
  def get_user!(%Scope{} = scope, id) do
    scope |> UserPolicy.scope(User) |> Repo.get!(id)
  end

  ## Registration and magic links

  @doc """
  Who may create an account (`SIGNUP_MODE`): `:open` — anyone; `:invite` — only an email
  with an open invitation (`StarterKit.Organizations.register_user/3` checks it);
  `:closed` — nobody. Existing users sign in in every mode.
  """
  def signup_mode, do: Application.get_env(:starter_kit, :signup_mode, :open)

  @doc """
  Registers a user and emails a magic link that confirms the address and signs in.
  `url_fun` receives the encoded token and returns the absolute URL.

  The user, the consent (`terms_accepted`, one acceptance per published terms/privacy
  version) and the audit event are written in one transaction: no account without its
  consent. The link leaves after the commit.

  Options: `invited: true` (the email has an open invitation; needed in `:invite` mode),
  `ip_address:` (kept with the consent).

  Refuses before any write: `{:error, :invitation_required}` (`:invite` mode, not invited),
  `{:error, :signup_closed}` (`:closed` mode), `{:error, :email_unavailable}` (no mail).
  """
  def register_user(attrs, url_fun, opts \\ []) when is_function(url_fun, 1) do
    with :ok <- require_signup_allowed(opts),
         :ok <- require_email_delivery(),
         {:ok, user} <- Repo.transact(fn -> insert_registered_user(attrs, opts) end) do
      deliver_magic_link(user, url_fun)
      {:ok, user}
    end
  end

  defp insert_registered_user(attrs, opts) do
    with {:ok, user} <- %User{} |> User.registration_changeset(attrs) |> Repo.insert(),
         {:ok, accepted} <- Legal.accept_at_signup(user, opts[:ip_address]),
         {:ok, _event} <-
           Audit.record("user.registered",
             actor: user,
             subject: user,
             metadata: %{accepted: accepted}
           ) do
      {:ok, user}
    end
  end

  defp require_signup_allowed(opts) do
    case {signup_mode(), Keyword.get(opts, :invited, false)} do
      {:open, _invited} -> :ok
      {:invite, true} -> :ok
      {:invite, false} -> {:error, :invitation_required}
      {:closed, _invited} -> {:error, :signup_closed}
    end
  end

  @doc """
  Makes `email` the first superadmin of a new installation (`mix starter_kit.admin.bootstrap`,
  `StarterKit.Release.bootstrap_admin/1`). It promotes the existing account, or creates a
  confirmed one without a password: the person signs in with a magic link or Google.
  Refused with `{:error, :already_bootstrapped}` once any superadmin exists, so it can
  never be used to take over a running installation.
  """
  def bootstrap_superadmin(email) when is_binary(email) do
    Repo.transact(fn ->
      Repo.query!("SELECT pg_advisory_xact_lock(hashtext('accounts.bootstrap_superadmin'))")

      cond do
        Repo.exists?(from u in User, where: u.role == :superadmin) ->
          {:error, :already_bootstrapped}

        user = get_user_by_email(String.trim(email)) ->
          promote_first_superadmin(user)

        true ->
          insert_first_superadmin(String.trim(email))
      end
    end)
  end

  defp insert_first_superadmin(email) do
    with {:ok, user} <- email |> User.bootstrap_changeset() |> Repo.insert(),
         do: promote_first_superadmin(user)
  end

  defp promote_first_superadmin(user) do
    with {:ok, user} <-
           user
           |> Ecto.Changeset.change(role: :superadmin, confirmed_at: user.confirmed_at || now())
           |> Repo.update(),
         {:ok, _event} <- Audit.record("user.superadmin_bootstrapped", subject: user) do
      {:ok, user}
    end
  end

  @doc "A blank registration changeset (for forms)."
  def change_registration(attrs \\ %{}),
    do: User.registration_changeset(%User{}, attrs, validate_unique: false)

  @doc """
  Emails a magic link when `email` belongs to a user. Returns `:ok` either way, so the
  response never reveals whether an account exists; `{:error, :email_unavailable}` (for
  everyone) when no mail can be sent.
  """
  def deliver_login_instructions(email, url_fun) when is_binary(email) do
    with :ok <- require_email_delivery() do
      case get_user_by_email(email) do
        %User{} = user -> deliver_magic_link(user, url_fun)
        nil -> :ok
      end

      :ok
    end
  end

  @doc """
  True when sign-up and sign-in links can be emailed. The sign-up and sign-in pages use
  it to say so up front; without it there is no link form and no "check your email".
  """
  def email_sign_in_available?, do: Notifications.email_available?()

  # Sign-up and sign-in links only work by email: refuse before any write when no mail
  # can leave, instead of a "check your inbox" that never arrives.
  defp require_email_delivery do
    if email_sign_in_available?(), do: :ok, else: {:error, :email_unavailable}
  end

  defp deliver_magic_link(user, url_fun) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    Notifications.notify(user, :magic_link, %{url: url_fun.(encoded_token)})
  end

  @doc "Gets the user behind a magic link token (nil when invalid or expired)."
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Signs in with a magic link. An unconfirmed user gets confirmed and every other token
  is expired. An unconfirmed user with a password cannot exist in this flow (passwords
  are only set after confirmation), so that case is refused.
  """
  def login_user_by_magic_link(token) do
    {:ok, query} = UserToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      {%User{confirmed_at: nil, hashed_password: hash}, _token} when not is_nil(hash) ->
        {:error, :not_found}

      {%User{confirmed_at: nil} = user, _token} ->
        user |> User.confirm_changeset() |> update_user_and_delete_all_tokens()

      {user, token} ->
        Repo.delete!(token)
        {:ok, {user, []}}

      nil ->
        {:error, :not_found}
    end
  end

  ## Google sign-in

  @doc """
  Finds or creates the user for a Google identity (`%{uid, email, email_verified, name,
  locale}`). An existing account with the same email is linked to the Google uid.

  Google must say the email is verified (`email_verified: true`); otherwise anyone could
  claim another person's address and take over their account.
  """
  def upsert_google_user(info, opts \\ [])

  def upsert_google_user(%{email_verified: true} = info, opts),
    do: do_upsert_google_user(info, opts)

  def upsert_google_user(_info, _opts), do: {:error, :email_not_verified}

  defp do_upsert_google_user(%{uid: uid, email: email} = info, opts) do
    cond do
      user = Repo.get_by(User, google_uid: uid) ->
        {:ok, user}

      user = get_user_by_email(email) ->
        user
        |> Ecto.Changeset.change(google_uid: uid, confirmed_at: user.confirmed_at || now())
        |> Repo.update()

      (refusal = require_signup_allowed(opts)) != :ok ->
        refusal

      true ->
        attrs = %{
          google_uid: uid,
          email: email,
          name: info[:name] || "",
          locale: info[:locale] || "en"
        }

        with {:ok, user} <- %User{} |> User.google_changeset(attrs) |> Repo.insert() do
          Audit.record("user.registered", actor: user, subject: user, metadata: %{via: "google"})
          {:ok, user}
        end
    end
  end

  ## Profile and settings

  @doc "A profile changeset (for forms)."
  def change_profile(user, attrs \\ %{}), do: User.profile_changeset(user, attrs)

  @doc "Updates name and locale."
  def update_profile(%Scope{user: user}, attrs) do
    user |> User.profile_changeset(attrs) |> Repo.update()
  end

  @doc """
  True when the last authentication was less than `minutes` ago (default 20).
  Sensitive changes (email, password) require it.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc "An email-change changeset (for forms)."
  def change_user_email(user, attrs \\ %{}, opts \\ []), do: User.email_changeset(user, attrs, opts)

  @doc """
  Validates the new email and sends a confirmation link to it. The email changes only
  when the user clicks that link (`update_user_email/2`). `{:error, :email_unavailable}`
  when no mail can be sent.
  """
  def request_email_change(%Scope{user: user}, attrs, url_fun) do
    changeset = User.email_changeset(user, attrs)

    with :ok <- require_email_delivery(),
         {:ok, applied} <- Ecto.Changeset.apply_action(changeset, :update) do
      {encoded_token, user_token} = UserToken.build_email_token(applied, "change:#{user.email}")
      Repo.insert!(user_token)
      Notifications.notify(applied, :email_change, %{url: url_fun.(encoded_token)})
      {:ok, applied}
    end
  end

  @doc """
  The new email behind an email-change link, without using the link (the confirmation
  page shows it; only `update_user_email/2` spends the token). `nil` when invalid.
  """
  def get_email_change(user, token) do
    with {:ok, query} <- UserToken.verify_change_email_token_query(token, "change:#{user.email}"),
         %UserToken{sent_to: email} <- Repo.one(query) do
      email
    else
      _ -> nil
    end
  end

  @doc "Changes the email when `token` matches. Expires all change-email tokens."
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :invalid_token}
      end
    end)
  end

  @doc "A password changeset (for forms)."
  def change_user_password(user, attrs \\ %{}, opts \\ []),
    do: User.password_changeset(user, attrs, opts)

  @doc """
  Sets a new password and expires every token of the user (all sessions end).
  Returns `{:ok, {user, expired_tokens}}`.
  """
  def update_user_password(%Scope{user: user}, attrs) do
    user |> User.password_changeset(attrs) |> update_user_and_delete_all_tokens()
  end

  @doc """
  Deletes the account. Memberships and tokens go with it (FK cascade). Legal acceptances
  stay as proof of consent (`user_id` becomes nil; the email hash remains).
  """
  def delete_user(%Scope{user: user}) do
    with {:ok, user} <- Repo.delete(user) do
      Audit.record("user.deleted", actor: user, subject: user)
      {:ok, user}
    end
  end

  @doc "Remembers the organization the user worked in last."
  def remember_organization(%User{} = user, organization_id) do
    user |> Ecto.Changeset.change(last_organization_id: organization_id) |> Repo.update()
  end

  ## Optional email (one-click unsubscribe)

  @doc """
  The user behind an unsubscribe token (`Notifications.unsubscribe_url/2`):
  `{:ok, user}`, or `:error` for a bad token, a deleted user or a changed address.
  """
  def get_user_by_unsubscribe_token(token) do
    with {:ok, user_id, hash} <- Notifications.verify_unsubscribe_token(token),
         {:ok, _} <- Ecto.UUID.cast(user_id),
         %User{} = user <- Repo.get(User, user_id),
         true <- Notifications.email_hash(user.email) == hash do
      {:ok, user}
    else
      _ -> :error
    end
  end

  @doc """
  Stops optional (lifecycle, marketing) mail for the user behind `token`. Idempotent:
  a second call is `:ok` and records nothing. `:error` for a token that names nobody.
  """
  def unsubscribe_from_optional_emails(token) do
    case get_user_by_unsubscribe_token(token) do
      {:ok, %User{optional_emails: false}} ->
        :ok

      {:ok, user} ->
        {:ok, user} = user |> Ecto.Changeset.change(optional_emails: false) |> Repo.update()
        Audit.record("user.optional_emails_stopped", actor: user, subject: user)
        :ok

      :error ->
        :error
    end
  end

  @doc """
  Turns optional mail on or off from settings (`%{"optional_emails" => true}` subscribes
  again after an unsubscribe). Audited only when the value changes.
  """
  def update_email_preferences(%Scope{user: user} = scope, attrs) do
    changeset = User.email_preferences_changeset(user, attrs)

    case Ecto.Changeset.fetch_change(changeset, :optional_emails) do
      {:ok, true} -> update_audited(changeset, scope, "user.optional_emails_started")
      {:ok, false} -> update_audited(changeset, scope, "user.optional_emails_stopped")
      :error -> Repo.update(changeset)
    end
  end

  defp update_audited(changeset, scope, action) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        Audit.record(action, scope: scope, subject: user)
        {:ok, user}
      end
    end)
  end

  ## Sessions

  @doc "Creates a session token for `user`; `device` may hold `:user_agent` and `:ip_address`."
  def generate_user_session_token(user, device \\ %{}) do
    {token, user_token} = UserToken.build_session_token(user, device)
    Repo.insert!(user_token)
    token
  end

  @doc "Returns `{user, token_inserted_at}` for a valid session token, else nil."
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc "Deletes one session token."
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  @doc "The live sessions of the scope's user, newest first."
  def list_sessions(%Scope{user: user}) do
    Repo.all(
      from t in UserToken,
        where: t.user_id == ^user.id and t.context == "session",
        order_by: [desc: t.inserted_at]
    )
  end

  @doc "Ends one of the user's sessions. Returns the deleted token (to disconnect it)."
  def revoke_session(%Scope{user: user}, session_id) do
    case Repo.get_by(UserToken, id: session_id, user_id: user.id, context: "session") do
      nil -> {:error, :not_found}
      token -> Repo.delete(token)
    end
  end

  ## Administration (superadmin)

  @doc "Lists users for the admin area (search by email or name)."
  def list_users(%Scope{} = scope, params) do
    search = params |> Map.get("q", "") |> String.trim()

    query =
      from u in UserPolicy.scope(scope, User), order_by: [desc: u.inserted_at]

    query =
      if search == "",
        do: query,
        else: where(query, [u], ilike(u.email, ^"%#{search}%") or ilike(u.name, ^"%#{search}%"))

    Repo.paginate(query, params)
  end

  @doc "Number of users (admin dashboard)."
  def count_users, do: Repo.aggregate(User, :count)

  @doc "Changes a user's global role (superadmin only; audited)."
  def update_user_role(%Scope{} = scope, %User{} = user, attrs) do
    with {:ok, updated} <- user |> User.role_changeset(attrs) |> Repo.update() do
      Audit.record("user.role_changed",
        scope: scope,
        subject: updated,
        metadata: %{from: user.role, to: updated.role}
      )

      {:ok, updated}
    end
  end

  @doc """
  Starts impersonating `target` (never another superadmin). Records an impersonation
  row and an audit event. Returns `{:ok, impersonation}`.
  """
  def start_impersonation(%Scope{user: admin} = scope, %User{} = target, attrs) do
    cond do
      not Scope.superadmin?(scope) or scope.impersonator ->
        {:error, :forbidden}

      target.role == :superadmin or target.id == admin.id ->
        {:error, :forbidden}

      true ->
        %Impersonation{admin_id: admin.id, target_user_id: target.id}
        |> Impersonation.changeset(attrs)
        |> Repo.insert()
        |> tap(fn
          {:ok, imp} ->
            Audit.record("impersonation.started",
              scope: scope,
              subject: target,
              metadata: %{reason: imp.reason, impersonation_id: imp.id}
            )

          _ ->
            :ok
        end)
    end
  end

  @doc "Ends the running impersonation of `scope` (audited)."
  def stop_impersonation(%Scope{impersonator: %User{} = admin, user: target} = scope) do
    from(i in Impersonation,
      where: i.admin_id == ^admin.id and i.target_user_id == ^target.id and is_nil(i.ended_at)
    )
    |> Repo.update_all(set: [ended_at: now()])

    Audit.record("impersonation.stopped", scope: scope, subject: target)
    {:ok, admin}
  end

  def stop_impersonation(_scope), do: {:error, :not_impersonating}

  ## Helpers

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end

  defp now, do: DateTime.utc_now(:second)
end
