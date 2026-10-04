defmodule StarterKitWeb.Plugs.VerifyAuthorized do
  @moduledoc """
  Pundit's `verify_authorized`: every action in an authenticated pipeline must call
  `authorize!/3` or `skip_authorization/1`. A missing check raises in dev/test and is
  reported (and answered 403) in production.
  """

  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    register_before_send(conn, fn conn ->
      cond do
        conn.private[:authorized] -> conn
        # A pipeline plug halted before any action ran (redirect to sign in, sudo mode…).
        is_nil(conn.private[:phoenix_action]) -> conn
        conn.status in [401, 403, 404, 429] or conn.status >= 500 -> conn
        true -> missing(conn)
      end
    end)
  end

  defp missing(conn) do
    controller = conn.private[:phoenix_controller]
    action = conn.private[:phoenix_action]
    message = "#{inspect(controller)}.#{action} did not call authorize!/3 or skip_authorization/1"

    if Application.get_env(:starter_kit, :raise_on_missing_authorization, true) do
      raise message
    else
      StarterKit.Monitoring.report(%RuntimeError{message: message})
      conn |> resp(403, "Forbidden")
    end
  end
end
