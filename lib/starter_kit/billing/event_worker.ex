defmodule StarterKit.Billing.EventWorker do
  @moduledoc "Reconciles one Stripe event in the background. ONE context call, as every worker."

  use Oban.Worker, queue: :default, max_attempts: 10, unique: [keys: [:event_id], period: 300]

  alias StarterKit.Billing

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"event_id" => id}}), do: Billing.process_event(id)
end
