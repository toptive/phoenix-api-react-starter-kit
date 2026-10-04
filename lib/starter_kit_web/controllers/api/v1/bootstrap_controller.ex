defmodule StarterKitWeb.Api.V1.BootstrapController do
  @moduledoc "Public SPA bootstrap, optionally personalized by a bearer session."
  use StarterKitWeb, :controller
  alias StarterKit.Organizations

  def show(conn, _params) do
    conn = skip_authorization(conn)
    data = Organizations.bootstrap(scope(conn), locale(conn))
    render_data(conn, {Serializers.BootstrapSerializer, data})
  end
end
