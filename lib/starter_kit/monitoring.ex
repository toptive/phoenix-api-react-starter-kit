defmodule StarterKit.Monitoring do
  @moduledoc """
  The ONE call site for error monitoring. Sentry is off unless `SENTRY_DSN` is set.
  Uncaught exceptions (plugs, Oban jobs, crashed processes) are reported automatically;
  call `report/2` only for errors you rescue on purpose.

  Privacy: no request bodies, no cookies, no PII except the user id (see docs/SECURITY.md).
  """

  use Boundary, top_level?: true, deps: [], exports: []

  @doc "Reports a rescued exception with extra context."
  def report(exception, context \\ %{}) do
    if enabled?() do
      Sentry.capture_exception(exception, extra: context)
    end

    :ok
  end

  @doc "Tags the current process's errors with the user id (never email or name)."
  def set_user(nil), do: :ok
  def set_user(user_id), do: Sentry.Context.set_user_context(%{id: user_id})

  @doc "True when a DSN is configured."
  def enabled?, do: not is_nil(Application.get_env(:sentry, :dsn))

  @doc false
  # Sentry `before_send`: strip anything personal the SDK may have collected.
  def scrub(event) do
    %{
      event
      | request: %{
          event.request
          | cookies: %{},
            data: nil,
            headers:
              Map.drop(event.request.headers || %{}, ["cookie", "authorization", "x-csrf-token"])
        }
    }
  end
end
