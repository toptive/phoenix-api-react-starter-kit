defmodule StarterKitWeb.Plugs.VerifyTurnstile do
  @moduledoc """
  Runs the Turnstile check (`StarterKit.AbuseProtection.verify/3`) before an anonymous
  action that creates work. Per controller action:

      plug StarterKitWeb.Plugs.VerifyTurnstile, "registration" when action == :create

  The API token comes as flat `turnstileToken`; nested params remain supported.
  A refused check returns 422 validation message keys for API requests before the action
  runs. Off = no-op.
  """

  @behaviour Plug

  import Plug.Conn
  import StarterKitWeb.Authorization, only: [skip_authorization: 1]

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
        %{"turnstile_token" => token} -> token
        _ -> nil
      end

    case AbuseProtection.verify(token, action, conn.remote_ip) do
      :ok ->
        conn

      {:error, :verification_required} ->
        conn = skip_authorization(conn)

        conn
        |> StarterKitWeb.Responses.render_error(422, :turnstile_failed, %{
          turnstile_token: [
            StarterKit.I18n.field_error(
              "validation.turnstile_required",
              %{},
              StarterKitWeb.Responses.locale(conn)
            )
          ]
        })
        |> halt()
    end
  end
end
