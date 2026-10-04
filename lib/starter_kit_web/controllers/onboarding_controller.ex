defmodule StarterKitWeb.OnboardingController do
  @moduledoc """
  First-run steps for a new organization. The dashboard sends a manager here until the
  organization is onboarded. The starter asks one optional question (the organization's
  name); a product replaces the steps with its own.
  """
  use StarterKitWeb, :controller
  use Typelizer.InertiaPage

  alias StarterKit.{Analytics, Organizations}

  page "onboarding/edit", props: [organization_name: :string]

  def edit(conn, _params) do
    scope = scope(conn)
    conn = authorize!(conn, :update, scope.organization)

    if Organizations.onboarding_required?(scope) do
      render_inertia(conn, "onboarding/edit", %{organization_name: scope.organization.name})
    else
      redirect(conn, to: ~p"/dashboard")
    end
  end

  def update(conn, params) do
    scope = scope(conn)
    conn = authorize!(conn, :update, scope.organization)

    answers = params["onboarding"] || %{}
    skipped = Enum.all?(Map.values(answers), &(&1 in [nil, ""]))

    result =
      scope
      |> Organizations.complete_onboarding(answers)
      |> Analytics.track_after_commit("onboarding_completed", scope, %{skipped: skipped})

    case result do
      {:ok, _} ->
        conn |> put_flash_t(:info, "flash.onboarding.done") |> redirect(to: ~p"/dashboard")

      {:error, changeset} ->
        conn |> assign_changeset_errors(changeset) |> redirect(to: ~p"/onboarding/edit")
    end
  end
end
