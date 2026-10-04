defmodule StarterKitWeb.ErrorPages do
  @moduledoc """
  Wraps every controller action: a denied policy (403) or a missing record (404)
  renders the Inertia page `errors/show` (or the JSON error envelope under `/api`)
  instead of the bare error page, so the user stays inside the app shell.
  """

  use Typelizer.InertiaPage

  import Plug.Conn

  page "errors/show", props: [status: :integer]

  alias StarterKitWeb.{Authorization, Responses}

  @doc false
  def call_action(conn, controller, action) do
    apply(controller, action, [conn, conn.params])
  rescue
    error in [StarterKitWeb.NotAuthorizedError] -> render_error(conn, 403, error)
    error in [Ecto.NoResultsError] -> render_error(conn, 404, error)
  end

  defp render_error(conn, status, error) do
    conn = Authorization.skip_authorization(conn)

    cond do
      String.starts_with?(conn.request_path, "/api/") ->
        Responses.render_error(conn, status, if(status == 403, do: :forbidden, else: :not_found))

      Map.has_key?(conn.private, :inertia_version) ->
        conn
        |> put_status(status)
        |> Inertia.Controller.render_inertia("errors/show", %{status: status})

      true ->
        reraise error, []
    end
  end
end
