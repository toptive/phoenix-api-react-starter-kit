defmodule StarterKit.Analytics.Events do
  @moduledoc """
  The catalogue of analytics events. An event not listed here raises in dev/test and is
  dropped in production. `origin` says who may send it (`:server`, `:client` through
  `POST /api/v1/events`, or `:both`).

  `props` maps each allowed property to its rule. A value that breaks its rule is dropped,
  and so is any property not listed, before anything leaves the app:

    * `["a", "b"]` — one of these values (atoms are accepted and sent as strings);
    * `:boolean`;
    * `{:count, max}` — an integer from 0 to `max`;
    * `{:slug, max}` — a short identifier: letters, digits, `_`, `.`, `-` (a page type,
      a locale, a host, a utm value). No spaces, `@`, `/` or `:`, so never an email or a URL;
    * `{:path, max}` — a path of a PUBLIC page (`/es/legal/terms`): no query, no fragment.

  Never free text, user input, emails, URLs with a query, or ids of other records.

  The funnel events (`signup_started` … `subscription_canceled`) are the default funnel of
  every product: keep their names so the PostHog funnels work in every app.
  """

  @plans_rule {:slug, 40}

  @events %{
    # Funnel
    "signup_started" => %{origin: :server, props: %{via: ~w(email google)}},
    "user_registered" => %{origin: :server, props: %{via: ~w(email google)}},
    "signup_confirmed" => %{origin: :server, props: %{}},
    "onboarding_completed" => %{origin: :server, props: %{skipped: :boolean}},
    "checkout_started" => %{
      origin: :server,
      props: %{plan: @plans_rule, interval: ~w(month year), mode: ~w(test live)}
    },
    "subscription_started" => %{
      origin: :server,
      props: %{plan: @plans_rule, interval: ~w(month year), mode: ~w(test live)}
    },
    "subscription_canceled" => %{
      origin: :server,
      props: %{plan: @plans_rule, mode: ~w(test live)}
    },
    # Accounts and teams
    "user_signed_in" => %{origin: :server, props: %{method: ~w(magic_link password google)}},
    "organization_created" => %{origin: :server, props: %{}},
    "invitation_sent" => %{origin: :server, props: %{role: ~w(owner admin member)}},
    "invitation_accepted" => %{origin: :server, props: %{}},
    # Traffic
    "public_page_viewed" => %{
      origin: :server,
      props: %{
        page_type: {:slug, 80},
        locale: {:slug, 10},
        path: {:path, 200},
        referrer_domain: {:slug, 255},
        utm_source: {:slug, 80},
        utm_medium: {:slug, 80},
        utm_campaign: {:slug, 80}
      }
    },
    "page_viewed" => %{origin: :client, props: %{page: {:slug, 80}}},
    "cta_clicked" => %{origin: :client, props: %{cta: {:slug, 40}, page: {:slug, 80}}}
  }

  @doc "The definition of `name`, or nil."
  def fetch(name), do: Map.get(@events, name)

  @doc "All event names."
  def names, do: Map.keys(@events)

  @doc """
  The properties that follow `rules`, with string keys. Unknown keys and invalid values are
  dropped; input is never turned into atoms.
  """
  def properties(props, rules) when is_map(props) do
    for {key, rule} <- rules,
        value <- [Map.get(props, key, Map.get(props, Atom.to_string(key)))],
        {:ok, safe} <- [cast(value, rule)],
        into: %{},
        do: {Atom.to_string(key), safe}
  end

  def properties(_, _), do: %{}

  defp cast(value, :boolean) when is_boolean(value), do: {:ok, value}

  defp cast(value, {:count, max}) when is_integer(value) and value >= 0 and value <= max,
    do: {:ok, value}

  defp cast(value, {:slug, max}) when is_binary(value) and byte_size(value) in 1..max//1 do
    if chars?(value, ~c""), do: {:ok, value}, else: :error
  end

  defp cast("/" <> rest = value, {:path, max}) when byte_size(value) <= max do
    if chars?(rest, ~c"/"), do: {:ok, value}, else: :error
  end

  defp cast(value, values) when is_atom(value) and not is_nil(value) and is_list(values),
    do: cast(Atom.to_string(value), values)

  defp cast(value, values) when is_list(values) do
    if value in values, do: {:ok, value}, else: :error
  end

  defp cast(_, _), do: :error

  # Letters, digits, `_`, `.`, `-`, and the `extra` characters.
  defp chars?(value, extra),
    do: value |> :binary.bin_to_list() |> Enum.all?(&(safe_char?(&1) or &1 in extra))

  defp safe_char?(c), do: c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c in ~c"_.-"
end
