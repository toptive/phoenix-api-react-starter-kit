defmodule StarterKitWeb.ErrorPages do
  @moduledoc "Converts policy denial and missing records to API error envelopes."
  alias StarterKitWeb.{Authorization, Responses}

  @doc false
  def call_action(conn, controller, action) do
    apply(controller, action, [conn, conn.params])
  rescue
    StarterKitWeb.NotAuthorizedError -> render_error(conn, 403, :forbidden)
    Ecto.NoResultsError -> render_error(conn, 404, :not_found)
  end

  defp render_error(conn, status, code),
    do: conn |> Authorization.skip_authorization() |> Responses.render_error(status, code)
end
