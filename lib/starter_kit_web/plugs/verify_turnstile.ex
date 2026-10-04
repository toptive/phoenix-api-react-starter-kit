defmodule StarterKitWeb.Plugs.VerifyTurnstile do
  @moduledoc """
  Runs the Turnstile check (`StarterKit.AbuseProtection.verify/3`) before an anonymous
  action that creates work. Per controller action:

      plug StarterKitWeb.Plugs.VerifyTurnstile, "registration" when action == :create

  The token comes as `user[turnstileToken]`. A refused check halts with a translated error
  on `turnstileToken` and goes back to the form; the action never runs. Off = no-op.
  """

  @behaviour Plug

  use StarterKitWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2]
  import StarterKitWeb.Authorization, only: [skip_authorization: 1]
  import StarterKitWeb.Responses, only: [assign_error: 3]

  alias StarterKit.AbuseProtection

  @impl true
  def init(action) when is_binary(action) do
    if action in AbuseProtection.actions(),
      do: action,
      else: raise(ArgumentError, "unknown Turnstile action #{inspect(action)}")
  end

  @impl true
  def call(conn, action) do
    token =
      case conn.params do
        %{"user" => %{"turnstile_token" => token}} -> token
        _ -> nil
      end

    case AbuseProtection.verify(token, action, conn.remote_ip) do
      :ok ->
        conn

      {:error, :verification_required} ->
        conn
        |> skip_authorization()
        |> assign_error(:turnstile_token, "validation.turnstile_required")
        |> redirect(to: form_path(action))
        |> halt()
    end
  end

  defp form_path("registration"), do: ~p"/registration/new"
  defp form_path("magic_link"), do: ~p"/session/new"
end
