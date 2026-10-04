defmodule StarterKit.Legal.LegalDocumentPolicy do
  @moduledoc "Anyone reads published documents; superadmins write versions and publish."

  @behaviour StarterKit.Policy

  @impl true
  def authorize(_scope, :show, _), do: true

  def authorize(%{user: %{role: :superadmin}, impersonator: nil}, action, _)
      when action in [:index, :edit, :new, :create, :update],
      do: true

  def authorize(_scope, _action, _resource), do: false
end
