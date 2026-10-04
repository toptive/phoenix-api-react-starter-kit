defmodule StarterKitWeb.RateLimit do
  @moduledoc """
  Fixed-window rate limits in ETS (Hammer). No Redis: one node per app. Used by the
  `rate_limit/2` plug on every unauthenticated endpoint that does work.
  """

  use Hammer, backend: :ets
end
