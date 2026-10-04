defmodule StarterKit.Notifications.DeliveryWorker do
  @moduledoc "Delivers one notification in the background. ONE context call, as every worker."

  use Oban.Worker, queue: :default, max_attempts: 5

  alias StarterKit.Notifications

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}), do: Notifications.deliver_now(args)
end
