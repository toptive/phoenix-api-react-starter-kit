defmodule StarterKitWeb.Api.V1.Auth.CurrentUserController do
  @moduledoc "Returns the current bearer token's user."
  use StarterKitWeb, :controller

  def show(conn, _params) do
    conn = authorize!(conn, :show, scope(conn).user)
    render_data(conn, {Serializers.UserSerializer, scope(conn).user})
  end
end
