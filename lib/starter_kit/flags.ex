defmodule StarterKit.Flags do
  @moduledoc """
  Feature flags: every on/off switch of the product, declared in ONE place.

      Flags.enabled?(:billing)

  Each flag below lists its environment variable, its default, whether React may see it
  (`public: true`, sent as the `flags` shared prop and typed by typelizer). Values are
  read in `config/runtime.exs` into `config :starter_kit, StarterKit.Flags`.

  At boot (`check_on_boot: true`, production) `StarterKit.Application` calls `check!/1`
  with the readiness check of each flag that needs a setup (a function that returns a list
  of problems): a flag that is ON but not ready stops the boot instead of failing at the
  first customer.

  Tests never change the global config: `with_flag/3` and `put_flag/2` (test/support)
  override a flag for the test process and the processes it starts, so tests stay async.
  """

  use Boundary, top_level?: true, deps: [], exports: []

  @flags [
    billing: [
      env: "BILLING_ENABLED",
      default: false,
      public: true,
      doc: "Paid plans: the billing page, checkout and plan limits."
    ],
    billing_renewal_notices: [
      env: "BILLING_RENEWAL_NOTICES",
      default: false,
      doc: "Renewal reminder emails before a yearly plan renews."
    ],
    site_indexing: [
      env: "SITE_INDEXING",
      default: true,
      doc: "Search engines may index the site (production starts locked until launch)."
    ],
    turnstile: [
      env: "TURNSTILE_REQUIRED",
      default: false,
      doc: "Sign-up and \"email me a link\" must pass a Cloudflare Turnstile challenge."
    ]
  ]

  @names Keyword.keys(@flags)
  @public for {name, opts} <- @flags, opts[:public], do: name
  @overrides? Application.compile_env(:starter_kit, [__MODULE__, :test_overrides], false)

  @doc "Every declared flag: `{name, opts}`."
  def all, do: @flags

  @doc "The names of the flags React may see."
  def public_names, do: @public

  @doc "True when `name` is ON. An unknown name raises (a typo is a bug, not OFF)."
  def enabled?(name) when name in @names do
    case override(name) do
      {:ok, value} -> value
      :none -> config() |> Keyword.get(name, @flags[name][:default]) |> Kernel.==(true)
    end
  end

  def enabled?(name), do: raise(ArgumentError, "unknown flag #{inspect(name)}")

  @doc "The public flags as `%{name => boolean}`, for the `flags` shared prop."
  def public, do: Map.new(@public, &{&1, enabled?(&1)})

  @doc "True in production: `StarterKit.Application` runs `check!/1` at boot."
  def check_on_boot?, do: Keyword.get(config(), :check_on_boot) == true

  @doc """
  Raises when a flag that is ON is not ready. `checks` maps a flag to a function that
  returns its problems (`[]` = ready).
  """
  def check!(checks) do
    case problems(checks) do
      [] -> :ok
      problems -> raise "flags are ON but not ready:\n  " <> Enum.join(problems, "\n  ")
    end
  end

  @doc "The problems of every flag in `checks` that is ON, as `\"ENV_NAME: problem\"` lines."
  def problems(checks) do
    for {name, check} <- checks,
        enabled?(name),
        problem <- check.(),
        do: "#{@flags[name][:env]}: #{problem}"
  end

  # A boolean set by `put_override/2` in this process, else in the process that started
  # this one (Task, Oban inline job, …). Production never sets one.
  defp override(name) do
    key = {__MODULE__, name}

    case Process.get(key) do
      value when is_boolean(value) -> {:ok, value}
      _ -> caller_override(key)
    end
  end

  # Test overrides: compiled in only with `test_overrides: true` (config/test.exs).
  if @overrides? do
    @doc false
    def put_override(name, value) when name in @names and is_boolean(value) do
      Process.put({__MODULE__, name}, value)
      :ok
    end

    @doc false
    def delete_override(name) when name in @names do
      Process.delete({__MODULE__, name})
      :ok
    end

    defp caller_override(key) do
      Enum.find_value(Process.get(:"$callers", []), :none, fn pid ->
        with {:dictionary, dict} <- Process.info(pid, :dictionary),
             {^key, value} when is_boolean(value) <- List.keyfind(dict, key, 0) do
          {:ok, value}
        else
          _ -> nil
        end
      end)
    end
  else
    defp caller_override(_key), do: :none
  end

  defp config, do: Application.get_env(:starter_kit, __MODULE__, [])
end
