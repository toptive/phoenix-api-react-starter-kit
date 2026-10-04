defmodule StarterKit.FlagHelpers do
  @moduledoc """
  Switch a feature flag in a test without touching the global config, so the test can
  stay `async: true`. The value holds for the test process and the processes it starts
  (Tasks, inline Oban jobs, the controller of a ConnTest request).

      with_flag(:billing, false, fn -> ... end)

      setup do: put_flag(:site_indexing, false)
  """

  use Boundary, top_level?: true, check: [in: false, out: false]

  alias StarterKit.Flags

  @doc "Runs `fun` with `name` set to `value`, then restores the previous value."
  def with_flag(name, value, fun) do
    previous = Process.get({Flags, name})
    Flags.put_override(name, value)

    try do
      fun.()
    after
      if is_nil(previous),
        do: Flags.delete_override(name),
        else: Flags.put_override(name, previous)
    end
  end

  @doc "Sets `name` to `value` for the rest of the test. Returns `:ok` (usable in `setup`)."
  def put_flag(name, value), do: Flags.put_override(name, value)
end
