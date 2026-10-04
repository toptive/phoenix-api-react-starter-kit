defmodule StarterKit.Accounts.TokenCleanupWorker do
  @moduledoc "Purges expired emailed tokens and sessions retained for thirty days."
  use Oban.Worker, queue: :default
  @impl true
  def perform(_job), do: StarterKit.Accounts.purge_expired_tokens()
end
