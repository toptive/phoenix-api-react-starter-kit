defmodule StarterKit.Mailer do
  @moduledoc """
  Swoosh mailer. Adapter per environment: `Local` (dev, see /dev/mailbox), `Test`,
  and `Postmark` in production when `POSTMARK_API_KEY` is set (config/runtime.exs).
  Send mail through `StarterKit.Notifications`, not directly.
  """

  use Boundary, top_level?: true, deps: [], exports: []
  use Swoosh.Mailer, otp_app: :starter_kit

  @doc """
  The From header `{name, address}` for a recipient's locale: `config :starter_kit,
  :mail_from_by_locale` (env `MAIL_FROM_ES` / `MAIL_FROM_NAME_ES`), else `:mail_from`.
  """
  def from(locale \\ nil) do
    default = Application.get_env(:starter_kit, :mail_from, {"StarterKit", "hello@example.com"})
    by_locale = Application.get_env(:starter_kit, :mail_from_by_locale, %{})

    Map.get(by_locale, locale |> to_string() |> String.downcase(), default)
  end
end
