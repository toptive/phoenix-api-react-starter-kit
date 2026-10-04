defmodule StarterKitWeb.JobsAccess do
  @moduledoc "Five-minute signed access to Oban Web, bound to a live superadmin bearer session."
  @behaviour Plug
  @behaviour Oban.Web.Resolver
  import Plug.Conn
  alias StarterKit.Accounts
  alias StarterKitWeb.{Endpoint, Responses}

  @cookie "_starter_kit_jobs"
  @salt "jobs-access"
  @max_age 300

  @doc "Mints a restricted HttpOnly cookie; the bearer itself never enters the browser session."
  def mint(conn, session_id) do
    token = Phoenix.Token.sign(Endpoint, @salt, session_id)

    put_resp_cookie(conn, @cookie, token,
      max_age: @max_age,
      path: "/admin/jobs",
      http_only: true,
      secure: conn.scheme == :https or Application.get_env(:starter_kit, :hsts, false),
      same_site: "Strict"
    )
  end

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    conn = fetch_cookies(conn)
    token = conn.cookies[@cookie]

    case verify(token) do
      {:ok, user} -> conn |> assign(:jobs_access, token) |> assign(:current_user, user)
      _ -> conn |> Responses.render_error(404, :not_found) |> halt()
    end
  end

  @doc "Verifies the grant's signature, age, revocation, expiry and current global role."
  def verify(token) when is_binary(token) do
    with {:ok, id} <- Phoenix.Token.verify(Endpoint, @salt, token, max_age: @max_age),
         do: Accounts.jobs_admin(id)
  end

  def verify(_token), do: {:error, :not_found}

  @impl Oban.Web.Resolver
  def resolve_user(conn), do: conn.assigns[:jobs_access]

  @impl Oban.Web.Resolver
  def resolve_access(token) do
    case verify(token) do
      {:ok, _} -> :all
      _ -> {:forbidden, "/session/new"}
    end
  end

  @doc "Rechecks permission on socket mount and every event; active sockets expire with the grant."
  def on_mount(:default, _params, %{"user" => token}, socket) do
    case verify(token) do
      {:ok, _} ->
        if Phoenix.LiveView.connected?(socket),
          do: Process.send_after(self(), :jobs_access_check, 1_000)

        socket =
          socket
          |> Phoenix.LiveView.attach_hook(:jobs_access_event, :handle_event, fn _event,
                                                                                _params,
                                                                                socket ->
            guard(token, socket)
          end)
          |> Phoenix.LiveView.attach_hook(:jobs_access_params, :handle_params, fn _params,
                                                                                  _uri,
                                                                                  socket ->
            guard(token, socket)
          end)
          |> Phoenix.LiveView.attach_hook(:jobs_access_info, :handle_info, fn
            message, socket -> check_info(message, token, socket)
          end)

        {:cont, socket}

      _ ->
        {:halt, Phoenix.LiveView.redirect(socket, to: "/session/new")}
    end
  end

  defp check_info(:jobs_access_check, token, socket) do
    case guard(token, socket) do
      {:cont, socket} ->
        Process.send_after(self(), :jobs_access_check, 1_000)
        {:halt, socket}

      result ->
        result
    end
  end

  defp check_info(_message, token, socket), do: guard(token, socket)

  defp guard(token, socket) do
    case verify(token) do
      {:ok, _} -> {:cont, socket}
      _ -> {:halt, Phoenix.LiveView.redirect(socket, to: "/session/new")}
    end
  end
end
