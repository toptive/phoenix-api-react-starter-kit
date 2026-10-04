defmodule StarterKit.I18n.Catalog do
  @moduledoc """
  Holds the runtime catalogue (compiled CSV reference overlaid with DB rows) in
  `:persistent_term`, one flat map per locale, plus a version string for caching.

  Reloads when any node broadcasts `{:reload, version}` on the `"i18n"` PubSub topic (an admin edit
  or a sync). `:persistent_term` makes reads free; writes are rare (admin edits).
  """

  use GenServer

  import Ecto.Query

  alias StarterKit.I18n.{Reference, Translation}
  alias StarterKit.Repo

  @topic "i18n"

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Flat map of key => text for `locale`."
  def get(locale) do
    :persistent_term.get({__MODULE__, locale}, nil) || Reference.catalog(locale)
  end

  @doc "Changes whenever the catalogue changes (ETag for the /locales endpoint)."
  def version, do: :persistent_term.get({__MODULE__, :version}, "reference")

  @doc "Rebuilds the catalogue on every node."
  def broadcast_reload do
    version = Ecto.UUID.generate()
    load(version)

    unless Application.get_env(:starter_kit, :i18n_inline_reload, false),
      do: Phoenix.PubSub.broadcast(StarterKit.PubSub, @topic, {:reload, version})
  end

  @doc false
  def reset_to_reference do
    for locale <- Reference.locales(),
        do: :persistent_term.put({__MODULE__, locale}, Reference.catalog(locale))

    :persistent_term.put({__MODULE__, :version}, "reference")
  end

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(StarterKit.PubSub, @topic)
    {:ok, %{}, {:continue, :load}}
  end

  @impl true
  def handle_continue(:load, state) do
    if Application.get_env(:starter_kit, :i18n_inline_reload, false),
      do: reset_to_reference(),
      else: load()

    {:noreply, state}
  end

  @impl true
  def handle_info({:reload, version}, state) do
    load(version)
    {:noreply, state}
  end

  defp load(reload_version \\ nil) do
    overrides =
      try do
        Repo.all(
          from t in Translation,
            where: t.edited or t.value != "",
            order_by: [t.locale, t.key],
            select: {t.locale, t.key, t.value, t.updated_at}
        )
      rescue
        # The table may not exist yet (first boot before migrations): use the reference.
        _ in [Postgrex.Error, DBConnection.ConnectionError] -> []
      end

    by_locale = Enum.group_by(overrides, &elem(&1, 0), &{elem(&1, 1), elem(&1, 2)})

    for locale <- Reference.locales() do
      catalog = Map.merge(Reference.catalog(locale), Map.new(Map.get(by_locale, locale, [])))
      :persistent_term.put({__MODULE__, locale}, catalog)
    end

    version =
      :crypto.hash(:md5, :erlang.term_to_binary(overrides))
      |> Base.url_encode64(padding: false)
      |> binary_part(0, 12)

    :persistent_term.put({__MODULE__, :version}, reload_version || version)
  end
end
