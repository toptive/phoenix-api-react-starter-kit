defmodule StarterKit.Accounts.Sessions do
  @moduledoc false
  import Ecto.Query
  alias StarterKit.{Accounts, Audit, Repo}
  alias StarterKit.Accounts.{Impersonation, Scope, Session, User, UserToken}

  def generate_api_token(user, device \\ %{}, opts \\ []) do
    encoded = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    timestamp = now()
    authenticated_at = opts[:authenticated_at] || timestamp
    impersonator_id = opts[:impersonator_user_id] || opts[:impersonator_id]

    session =
      Repo.insert!(%Session{
        user_id: user.id,
        token_hash: digest(encoded),
        organization_id: opts[:organization_id] || user.last_organization_id,
        expires_at: DateTime.add(timestamp, if(impersonator_id, do: 8, else: 336), :hour),
        authenticated_at: authenticated_at,
        sudo_until: if(is_nil(impersonator_id), do: DateTime.add(authenticated_at, 10, :minute)),
        impersonator_user_id: impersonator_id,
        impersonator_session_id: opts[:impersonator_session_id],
        impersonation_id: opts[:impersonation_id],
        user_agent: device[:user_agent] && String.slice(device[:user_agent], 0, 255),
        ip_address: device[:ip_address]
      })

    session_payload(user, Repo.preload(session, :impersonator_user), encoded, false)
  end

  def get_user_by_api_token(encoded) when is_binary(encoded) do
    case Repo.get_by(Session, token_hash: digest(encoded))
         |> Repo.preload([:user, :impersonator_user]) do
      nil -> nil
      session -> load_session(session)
    end
  end

  defp load_session(session) do
    if session.revoked_at || not DateTime.after?(session.expires_at, now()) do
      {:error, :session_expired}
    else
      session = touch(session)
      {session.user, session}
    end
  end

  defp touch(session) do
    timestamp = now()
    expiry_threshold = DateTime.add(timestamp, 7, :day)
    minute_threshold = DateTime.add(timestamp, -1, :minute)
    base = from s in Session, where: s.id == ^session.id and is_nil(s.revoked_at)

    cond do
      is_nil(session.impersonator_user_id) and
          DateTime.before?(session.expires_at, expiry_threshold) ->
        query = where(base, [s], s.expires_at < ^expiry_threshold)
        changes = [expires_at: DateTime.add(timestamp, 14, :day), last_used_at: timestamp]
        touch_if_current(session, query, changes)

      is_nil(session.last_used_at) or DateTime.before?(session.last_used_at, minute_threshold) ->
        query = where(base, [s], is_nil(s.last_used_at) or s.last_used_at < ^minute_threshold)
        touch_if_current(session, query, last_used_at: timestamp)

      true ->
        session
    end
  end

  defp touch_if_current(session, query, changes) do
    case Repo.update_all(query, set: changes) do
      {1, _} -> struct(session, changes)
      {0, _} -> Repo.reload!(session)
    end
  end

  def create_api_session(attrs, device, current \\ nil) do
    email = if is_binary(attrs["email"]), do: attrs["email"], else: ""
    password = if is_binary(attrs["password"]), do: attrs["password"], else: ""

    case Accounts.get_user_by_email_and_password(email, password) do
      %User{confirmed_at: confirmed} = user when not is_nil(confirmed) ->
        issue_or_refresh(user, device, current, false)

      _ ->
        {:error, :invalid_credentials}
    end
  end

  def create_magic_link_session(token, device, current \\ nil) do
    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
           {before, _row} <- Repo.one(lock(query, "FOR UPDATE")),
           {:ok, {user, _expired}} <- Accounts.login_user_by_magic_link(token) do
        issue_or_refresh(user, device, current, is_nil(before.confirmed_at))
      else
        _ -> {:error, :magic_link_invalid}
      end
    end)
  end

  defp issue_or_refresh(
         user,
         _device,
         %Session{user_id: id, impersonator_user_id: nil} = session,
         new?
       )
       when id == user.id do
    with {:ok, session} <- persist_sudo(session) do
      {:ok, session_payload(user, session, nil, new?)}
    end
  end

  defp issue_or_refresh(user, device, _current, new?),
    do: {:ok, Map.put(generate_api_token(user, device), :new_account, new?)}

  defp session_payload(user, session, encoded, new?) do
    %{
      token: encoded,
      session: session,
      expires_at: session.expires_at,
      sudo_until: session.sudo_until,
      user: user,
      impersonator: session.impersonator_user,
      new_account: new?
    }
  end

  def elevate_api_token(%Scope{user: user, impersonator: nil}, session, attrs) do
    Repo.transact(fn ->
      with :ok <- verify_sudo(user, attrs), do: persist_sudo(session)
    end)
  end

  def elevate_api_token(_scope, _session, _attrs), do: {:error, :forbidden}

  defp verify_sudo(_user, %{"magic_link_token" => _, "password" => _}), do: {:error, :bad_request}

  defp verify_sudo(_user, %{"magic_link_token" => token}) when not is_binary(token),
    do: {:error, :bad_request}

  defp verify_sudo(_user, %{"password" => password}) when not is_binary(password),
    do: {:error, :bad_request}

  defp verify_sudo(user, %{"magic_link_token" => token}) when is_binary(token) do
    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
           {%User{id: id}, row} <- Repo.one(lock(query, "FOR UPDATE")),
           true <- id == user.id,
           {:ok, _} <- Repo.delete(row) do
        {:ok, :verified}
      else
        _ -> {:error, :magic_link_invalid}
      end
    end)
    |> case do
      {:ok, :verified} -> :ok
      error -> error
    end
  end

  defp verify_sudo(%User{hashed_password: nil} = user, %{"password" => _}) do
    {:error,
     user |> Ecto.Changeset.change() |> Ecto.Changeset.add_error(:password, "validation.required")}
  end

  defp verify_sudo(user, %{"password" => password}) when is_binary(password) do
    if User.valid_password?(user, password), do: :ok, else: {:error, :invalid_credentials}
  end

  defp verify_sudo(_user, _attrs), do: {:error, :bad_request}

  defp persist_sudo(session) do
    Repo.transact(fn ->
      with {:ok, updated} <-
             session
             |> Ecto.Changeset.change(
               authenticated_at: now(),
               sudo_until: DateTime.add(now(), 10, :minute)
             )
             |> Repo.update() do
        Audit.record("user.sudo_authenticated", actor: Accounts.get_user!(session.user_id))
        {:ok, updated}
      end
    end)
  end

  def update_api_password(scope, attrs, device) do
    Repo.transact(fn ->
      with {:ok, {user, _expired}} <- Accounts.update_user_password(scope, attrs) do
        {:ok, generate_api_token(user, device, organization_id: scope.organization.id)}
      end
    end)
  end

  def set_session_organization(session, organization_id) do
    session |> Ecto.Changeset.change(organization_id: organization_id) |> Repo.update()
  end

  def delete_api_token(scope, session) do
    Repo.transact(fn ->
      if session.impersonator_user_id, do: end_impersonation(scope, session)
      ids = Enum.reject([session.id, session.impersonator_session_id], &is_nil/1)
      revoke_with_children(ids)
      Audit.record("session.revoked", scope: scope, subject: session)
      {:ok, :revoked}
    end)
    |> case do
      {:ok, :revoked} -> :ok
      error -> error
    end
  end

  def stop_api_impersonation(%Scope{impersonator: nil}, _session), do: {:error, :not_impersonating}

  def stop_api_impersonation(scope, session) do
    Repo.transact(fn ->
      end_impersonation(scope, session)
      revoke_with_children([session.id])
      {:ok, :stopped}
    end)
  end

  defp end_impersonation(scope, session) do
    if session.impersonation_id do
      Repo.update_all(
        from(i in StarterKit.Accounts.Impersonation, where: i.id == ^session.impersonation_id),
        set: [ended_at: now()]
      )
    end

    Audit.record("impersonation.stopped", scope: scope, subject: scope.user)
  end

  defp revoke_with_children(ids) do
    Repo.update_all(
      from(s in Session,
        where: s.id in ^ids or s.impersonator_session_id in ^ids
      ),
      set: [revoked_at: now()]
    )
  end

  def purge_expired_tokens do
    cutoff = DateTime.add(now(), -30, :day)
    Repo.delete_all(from s in Session, where: s.expires_at < ^cutoff or s.revoked_at < ^cutoff)

    Repo.delete_all(
      from t in UserToken,
        where:
          (t.context == "magic_link" and t.inserted_at < ago(15, "minute")) or
            (like(t.context, "change_email:%") and t.inserted_at < ago(7, "day")) or
            (t.context == "jobs_access" and t.inserted_at < ago(60, "second"))
    )

    Repo.delete_all(from i in Impersonation, where: i.ended_at < ago(90, "day"))
    :ok
  end

  defp digest(encoded), do: :crypto.hash(:sha256, encoded)
  defp now, do: DateTime.utc_now(:second)
end
