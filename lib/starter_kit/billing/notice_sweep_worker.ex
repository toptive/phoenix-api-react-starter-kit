defmodule StarterKit.Billing.NoticeSweepWorker do
  @moduledoc "Daily renewal-notice sweep (Oban Cron). ONE context call, as every worker."

  use Oban.Worker, queue: :default, max_attempts: 3

  alias StarterKit.Billing

  @impl Oban.Worker
  def perform(%Oban.Job{}), do: Billing.send_renewal_notices()
end
