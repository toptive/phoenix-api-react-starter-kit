defmodule StarterKitWeb.Api.V1.OnboardingController do
  @moduledoc "Onboards the current organization with optional answers."
  use StarterKitWeb, :controller
  alias StarterKit.{Analytics, Organizations}
  alias StarterKitWeb.ApiAuth

  def show(conn, _params) do
    conn = authorize!(conn, :update, scope(conn).organization)
    render_data(conn, {Serializers.OnboardingSerializer, Organizations.onboarding(scope(conn))})
  end

  def update(conn, params) do
    conn = authorize!(conn, :update, scope(conn).organization)
    attrs = Map.take(params, ["name"])

    case Organizations.complete_onboarding(scope(conn), attrs) do
      {:ok, org} ->
        skipped =
          Enum.all?(Map.values(attrs), &(is_nil(&1) or (is_binary(&1) and String.trim(&1) == "")))

        Analytics.track("onboarding_completed", scope(conn), %{skipped: skipped})
        render_data(conn, {Serializers.OrganizationSerializer, org})

      {:error, reason} ->
        ApiAuth.error(conn, reason)
    end
  end
end
