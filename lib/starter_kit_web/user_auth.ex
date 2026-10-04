defmodule StarterKitWeb.UserAuth do
  @moduledoc """
  Session authentication (phx.gen.auth 1.8 style) extended with the current
  organization and impersonation.

  Session keys: `:user_token`, `:organization_id`, `:impersonator_token` (the
  superadmin's own token while impersonating), `:user_return_to`.
  """

  use StarterKitWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias StarterKit.Accounts
  alias StarterKit.Accounts.Scope
  alias StarterKit.Organizations
  alias StarterKitWeb.Responses

  @max_cookie_age_in_days 14
  @remember_me_cookie "_starter_kit_web_user_remember_me"
  @remember_me_options [
    sign: true,
    max_age: @max_cookie_age_in_days * 24 * 60 * 60,
    same_site: "Lax",
    http_only: true
  ]
  @session_reissue_age_in_days 7

  @doc "Where signed-in users land."
  def signed_in_path, do: ~p"/dashboard"

  @doc """
  Logs the user in and redirects to `:user_return_to` or the dashboard. The session
  is renewed (fixation) and the device is recorded on the session token.
  """
  def log_in_user(conn, user, params \\ %{}) do
    user_return_to = get_session(conn, :user_return_to)

    conn
    |> create_or_extend_session(user, params)
    |> redirect(to: user_return_to || signed_in_path())
  end

  @doc "Logs the user out: deletes the token, clears the session and the remember-me cookie."
  def log_out_user(conn) do
    if token = get_session(conn, :user_token), do: Accounts.delete_user_session_token(token)
    if token = get_session(conn, :impersonator_token), do: Accounts.delete_user_session_token(token)

    conn
    |> renew_session(nil)
    |> delete_resp_cookie(@remember_me_cookie)
    |> redirect(to: ~p"/")
  end

  @doc """
  Loads the scope: user (session or remember-me cookie), current organization and
  impersonator. Anonymous requests get `current_scope: nil`.
  """
  def fetch_current_scope_for_user(conn, _opts) do
    with {token, conn} <- ensure_user_token(conn),
         {user, token_inserted_at} <- Accounts.get_user_by_session_token(token) do
      scope =
        user
        |> Scope.for_user()
        |> Scope.put_impersonator(impersonator(conn))
        |> Organizations.scope_for(get_session(conn, :organization_id))

      StarterKit.Monitoring.set_user(user.id)

      conn
      |> assign(:current_scope, scope)
      |> put_session(:organization_id, Scope.organization_id(scope))
      |> maybe_reissue_user_session_token(user, token_inserted_at)
    else
      nil -> assign(conn, :current_scope, nil)
    end
  end

  defp impersonator(conn) do
    with token when is_binary(token) <- get_session(conn, :impersonator_token),
         {admin, _} <- Accounts.get_user_by_session_token(token) do
      admin
    else
      _ -> nil
    end
  end

  defp ensure_user_token(conn) do
    if token = get_session(conn, :user_token) do
      {token, conn}
    else
      conn = fetch_cookies(conn, signed: [@remember_me_cookie])

      if token = conn.cookies[@remember_me_cookie] do
        {token, conn |> put_token_in_session(token) |> put_session(:user_remember_me, true)}
      else
        nil
      end
    end
  end

  defp maybe_reissue_user_session_token(conn, user, token_inserted_at) do
    token_age = DateTime.diff(DateTime.utc_now(:second), token_inserted_at, :day)

    if token_age >= @session_reissue_age_in_days and is_nil(get_session(conn, :impersonator_token)) do
      create_or_extend_session(conn, user, %{})
    else
      conn
    end
  end

  defp create_or_extend_session(conn, user, params) do
    token = Accounts.generate_user_session_token(user, device(conn))
    remember_me = get_session(conn, :user_remember_me)

    conn
    |> renew_session(user)
    |> put_token_in_session(token)
    |> maybe_write_remember_me_cookie(token, params, remember_me)
  end

  defp device(conn) do
    %{
      user_agent: conn |> get_req_header("user-agent") |> List.first(),
      ip_address: conn.remote_ip |> :inet.ntoa() |> to_string()
    }
  end

  # Keep the session when the same user re-authenticates (open tabs keep their CSRF token).
  defp renew_session(%{assigns: %{current_scope: %Scope{user: %{id: id}}}} = conn, %{id: id}),
    do: conn

  defp renew_session(conn, _user) do
    delete_csrf_token()
    locale = get_session(conn, :locale)

    conn
    |> configure_session(renew: true)
    |> clear_session()
    |> then(&if(locale, do: put_session(&1, :locale, locale), else: &1))
  end

  defp maybe_write_remember_me_cookie(conn, token, %{"remember_me" => value}, _)
       when value in ["true", true],
       do: write_remember_me_cookie(conn, token)

  defp maybe_write_remember_me_cookie(conn, token, _params, true),
    do: write_remember_me_cookie(conn, token)

  defp maybe_write_remember_me_cookie(conn, _token, _params, _), do: conn

  defp write_remember_me_cookie(conn, token) do
    conn
    |> put_session(:user_remember_me, true)
    |> put_resp_cookie(@remember_me_cookie, token, @remember_me_options)
  end

  defp put_token_in_session(conn, token), do: put_session(conn, :user_token, token)

  ## Impersonation

  @doc "Switches the session to `target` and keeps the admin's token aside."
  def start_impersonation(conn, target) do
    admin_token = get_session(conn, :user_token)
    token = Accounts.generate_user_session_token(target, device(conn))

    conn
    |> put_session(:impersonator_token, admin_token)
    |> put_session(:user_token, token)
    |> delete_session(:organization_id)
    |> delete_resp_cookie(@remember_me_cookie)
  end

  @doc "Ends impersonation and restores the admin session."
  def stop_impersonation(conn) do
    if token = get_session(conn, :user_token), do: Accounts.delete_user_session_token(token)

    conn
    |> put_session(:user_token, get_session(conn, :impersonator_token))
    |> delete_session(:impersonator_token)
    |> delete_session(:organization_id)
  end

  ## Plugs

  @doc "Requires a recent authentication (email, password and account changes)."
  def require_sudo_mode(conn, _opts) do
    if Accounts.sudo_mode?(conn.assigns.current_scope.user, -10) do
      conn
    else
      conn
      |> Responses.put_flash_t(:error, "flash.reauthenticate")
      |> maybe_store_return_to()
      |> redirect(external: Responses.spa_sign_in_url())
      |> halt()
    end
  end

  @doc "Sends signed-in users away from guest-only pages."
  def redirect_if_user_is_authenticated(conn, _opts) do
    if conn.assigns.current_scope do
      conn |> redirect(to: signed_in_path()) |> halt()
    else
      conn
    end
  end

  @doc "Requires a signed-in user."
  def require_authenticated_user(conn, _opts) do
    if conn.assigns.current_scope && conn.assigns.current_scope.user do
      conn
    else
      conn
      |> Responses.put_flash_t(:error, "flash.sign_in_required")
      |> maybe_store_return_to()
      |> redirect(external: Responses.spa_sign_in_url())
      |> halt()
    end
  end

  @doc "`/api` version of `require_authenticated_user/2`: 401 in the error envelope."
  def require_api_user(conn, _opts) do
    if conn.assigns.current_scope && conn.assigns.current_scope.user,
      do: conn,
      else: conn |> Responses.render_error(401, :unauthorized) |> halt()
  end

  @doc "Requires a superadmin who is not impersonating anyone."
  def require_superadmin(conn, _opts) do
    scope = conn.assigns.current_scope

    if Scope.superadmin?(scope) and is_nil(scope.impersonator) do
      conn
    else
      conn |> put_status(404) |> put_view(StarterKitWeb.ErrorHTML) |> render(:"404") |> halt()
    end
  end

  defp maybe_store_return_to(%{method: "GET"} = conn),
    do: put_session(conn, :user_return_to, current_path(conn))

  defp maybe_store_return_to(conn), do: conn
end
