defmodule StarterKit.Analytics do
  @moduledoc """
  The ONE call site for product analytics.

      Analytics.track("user_signed_in", user, %{method: "magic_link"})

  Events and their typed properties live in `StarterKit.Analytics.Events`: a property that
  breaks its rule is dropped, so free text, emails and URLs never leave the app. The adapter
  is chosen by config (`:log` by default, `:posthog` with `POSTHOG_API_KEY` and
  `POSTHOG_HOST`, `:test` in tests). Sending never blocks the caller and never raises in
  production: at most 8 deliveries run at once, each with short timeouts, and the rest are
  dropped. An event without a user (`nil` actor) is anonymous: a random id per event and
  no PostHog person profile. PostHog never geolocates (the IP would be the server's).

  Track a write after its transaction, never inside it (a rollback would leave a false
  event): `Repo.transact(...) |> Analytics.track_after_commit("checkout_started", scope)`.
  """

  use Boundary, top_level?: true, deps: [], exports: [Events]

  require Logger

  alias StarterKit.Analytics.Events

  @doc false
  def child_spec(_opts) do
    Supervisor.child_spec(
      {Task.Supervisor, name: __MODULE__.Supervisor, max_children: 8},
      id: __MODULE__
    )
  end

  @doc "Tracks `name` for `actor` (a user struct, a scope, or nil) with allowed `props`."
  def track(name, actor, props \\ %{}, opts \\ []) do
    client? = Keyword.get(opts, :client, false)

    case Events.fetch(name) do
      nil ->
        if not client? and raise_unknown?(),
          do: raise(ArgumentError, "unknown analytics event #{inspect(name)}")

        :ignored

      %{origin: :server} when client? ->
        :ignored

      %{props: rules} ->
        dispatch(%{
          event: name,
          distinct_id: distinct_id(actor),
          properties: Events.properties(props, rules) |> anonymize(anonymous?(actor))
        })
    end
  end

  @doc """
  Tracks `name` when `result` is `{:ok, _}` (a committed write) and returns `result`
  unchanged, so it ends a pipe: `Repo.transact(...) |> Analytics.track_after_commit(...)`.
  """
  def track_after_commit(result, name, actor, props \\ %{}) do
    with {:ok, _} <- result, do: track(name, actor, props)
    result
  end

  defp anonymize(props, true), do: Map.put(props, "$process_person_profile", false)
  defp anonymize(props, false), do: props

  defp distinct_id(%{user: %{id: id}}), do: id
  defp distinct_id(%{id: id}), do: id
  # No visitor identifier exists for anonymous events: each one gets a throwaway id and
  # PostHog is told not to build a person profile for it.
  defp distinct_id(_), do: Ecto.UUID.generate()

  defp anonymous?(%{user: %{id: _}}), do: false
  defp anonymous?(%{id: _}), do: false
  defp anonymous?(_), do: true

  defp dispatch(event) do
    case config(:adapter, :log) do
      :log ->
        Logger.debug("analytics #{event.event} #{inspect(event.properties)}")
        :ok

      :test ->
        send(self(), {:analytics, event})
        :ok

      :posthog ->
        deliver(event)

      _ ->
        :ignored
    end
  end

  # Fire and forget: when 8 deliveries are already running, the event is dropped.
  defp deliver(event) do
    case Task.Supervisor.start_child(__MODULE__.Supervisor, fn -> post_posthog(event) end) do
      {:ok, _pid} -> :ok
      _ -> :ignored
    end
  catch
    :exit, _ -> :ignored
  end

  defp post_posthog(event) do
    body = %{
      api_key: config(:posthog_api_key),
      event: event.event,
      distinct_id: event.distinct_id,
      properties: Map.put(event.properties, "$geoip_disable", true)
    }

    options =
      Keyword.merge(config(:request_options, []),
        json: body,
        retry: false,
        redirect: false,
        decode_body: false,
        receive_timeout: 2_000,
        pool_timeout: 1_000
      )

    Req.post(config(:posthog_host) <> "/capture/", options)
    :ok
  rescue
    _ -> :ignored
  end

  defp raise_unknown?, do: config(:raise_on_unknown, false)

  defp config(key, default \\ nil),
    do: Application.get_env(:starter_kit, __MODULE__, []) |> Keyword.get(key, default)
end
