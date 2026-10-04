defmodule StarterKit.FlagsTest do
  use StarterKit.DataCase, async: true

  alias StarterKit.Flags

  test "a flag reads its config, and an unknown name raises" do
    assert Flags.enabled?(:billing)
    refute Flags.enabled?(:billing_renewal_notices)
    assert_raise ArgumentError, ~r/unknown flag :made_up/, fn -> Flags.enabled?(:made_up) end
  end

  test "every flag declares its env var and a boolean default" do
    for {name, opts} <- Flags.all() do
      assert is_binary(opts[:env]), "#{name} has no env:"
      assert is_boolean(opts[:default]), "#{name} has no boolean default:"
    end
  end

  test "only public flags reach React" do
    assert Flags.public() == %{billing: true}
    put_flag(:billing, false)
    assert Flags.public() == %{billing: false}
  end

  test "with_flag/3 holds inside the block, in started processes, then restores" do
    with_flag(:site_indexing, false, fn ->
      refute Flags.enabled?(:site_indexing)
      refute Task.async(fn -> Flags.enabled?(:site_indexing) end) |> Task.await()

      with_flag(:site_indexing, true, fn -> assert Flags.enabled?(:site_indexing) end)
      refute Flags.enabled?(:site_indexing)
    end)

    assert Flags.enabled?(:site_indexing)
  end

  test "the boot check raises only for a flag that is ON and not ready" do
    not_ready = fn -> ["SOME_KEY is missing"] end

    assert_raise RuntimeError, ~r/BILLING_ENABLED: SOME_KEY is missing/, fn ->
      Flags.check!(billing: not_ready)
    end

    put_flag(:billing, false)
    assert :ok = Flags.check!(billing: not_ready)
    assert :ok = Flags.check!(billing: fn -> [] end)
  end
end
