defmodule StarterKitWeb.Api.V1.Settings.BillingController do
  @moduledoc "Tenant billing overview from the existing billing context."
  use StarterKitWeb, :controller
  alias StarterKit.Billing

  def show(conn, _params) do
    conn = authorize!(conn, :show, scope(conn).organization)

    case Billing.overview(scope(conn)) do
      {:ok, overview} -> render_data(conn, {Serializers.BillingOverviewSerializer, overview})
      {:error, reason} -> StarterKitWeb.BillingResponses.error(conn, reason)
    end
  end
end
