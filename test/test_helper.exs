# Each running test case holds one sandbox connection: never run more cases than the pool has.
pool_size = Application.fetch_env!(:starter_kit, StarterKit.Repo)[:pool_size]
ExUnit.start(max_cases: min(System.schedulers_online() * 2, pool_size))
Ecto.Adapters.SQL.Sandbox.mode(StarterKit.Repo, :manual)
