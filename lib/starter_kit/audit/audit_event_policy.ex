defmodule StarterKit.Audit.AuditEventPolicy do
  @moduledoc "Only superadmins read the audit log. Nobody changes it."

  @behaviour StarterKit.Policy

  @impl true
  def authorize(%{user: %{role: :superadmin}, impersonator: nil}, action, _)
      when action in [:index, :show],
      do: true

  def authorize(_scope, _action, _resource), do: false
end
