defmodule StarterKit.I18n.TranslationPolicy do
  @moduledoc "Only superadmins edit translations."

  @behaviour StarterKit.Policy

  @impl true
  def authorize(%{user: %{role: :superadmin}, impersonator: nil}, action, _)
      when action in [:index, :show, :update, :create],
      do: true

  def authorize(_scope, _action, _resource), do: false
end
