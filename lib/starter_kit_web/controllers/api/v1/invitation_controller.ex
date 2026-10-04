defmodule StarterKitWeb.Api.V1.InvitationController do
  @moduledoc "Peeks at an open invitation without accepting it."
  use StarterKitWeb, :controller
  alias StarterKit.Organizations
  alias StarterKitWeb.ApiAuth

  def show(conn, %{"token" => token}) do
    conn = skip_authorization(conn)

    case Organizations.invitation_preview(scope(conn), token) do
      {:ok, preview} -> render_data(conn, {Serializers.InvitationPreviewSerializer, preview})
      {:error, reason} -> ApiAuth.error(conn, reason)
    end
  end
end
