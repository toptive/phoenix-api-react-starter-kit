defmodule StarterKitWeb.Plugs.BearerAuth do
  @moduledoc "Loads the user, API token and tenant scope from an opaque bearer token."
  @behaviour Plug
  import Plug.Conn

  alias StarterKit.Accounts
  alias StarterKit.Accounts.{Scope, Session, User}
  alias StarterKit.Organizations
  alias StarterKitWeb.Responses

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    with [header] <- get_req_header(conn, "authorization"),
         [scheme, encoded] <- String.split(header, " ", parts: 2),
         true <- String.downcase(scheme) == "bearer",
         {%User{} = user, %Session{} = token} <- Accounts.get_user_by_api_token(encoded) do
      scope =
        user
        |> Scope.for_user()
        |> Scope.put_impersonator(token.impersonator_user)
        |> Organizations.scope_for(token.organization_id)

      {:ok, token} =
        if token.organization_id == scope.organization.id,
          do: {:ok, token},
          else: Accounts.set_session_organization(token, scope.organization.id)

      scope = %{scope | session: token}
      StarterKit.Monitoring.set_user(user.id)

      conn
      |> assign(:current_user, user)
      |> assign(:current_scope, scope)
      |> assign(:api_token, token)
    else
      {:error, :session_expired} ->
        conn |> Responses.render_error(401, :session_expired) |> halt()

      _ ->
        conn |> assign(:current_user, nil) |> assign(:current_scope, nil) |> assign(:api_token, nil)
    end
  end

  @doc "Requires a valid bearer token, with a JSON 401 on failure."
  def require_authenticated_api_user(conn, _opts) do
    if conn.assigns[:current_user],
      do: conn,
      else: conn |> Responses.render_error(401, :unauthorized) |> halt()
  end

  @doc "Requires this token's sudo window to be open."
  def require_sudo(conn, _opts) do
    with %{sudo_until: %DateTime{} = until} <- conn.assigns[:api_token],
         true <- DateTime.after?(until, DateTime.utc_now()),
         %{impersonator: nil} <- conn.assigns[:current_scope] do
      conn
    else
      _ -> conn |> Responses.render_error(403, :sudo_required) |> halt()
    end
  end

  @doc "Hides the superadmin area from anonymous, ordinary and impersonating callers."
  def require_superadmin(conn, _opts) do
    scope = conn.assigns[:current_scope]

    if Scope.superadmin?(scope) and is_nil(scope.impersonator),
      do: conn,
      else: conn |> Responses.render_error(404, :not_found) |> halt()
  end
end
