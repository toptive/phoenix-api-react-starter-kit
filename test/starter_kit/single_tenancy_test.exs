defmodule StarterKit.SingleTenancyTest do
  # Changes global config (tenancy mode): must not run next to async tests.
  use StarterKit.DataCase, async: false

  setup do
    Application.put_env(:starter_kit, :tenancy, :single)
    on_exit(fn -> Application.put_env(:starter_kit, :tenancy, :multi) end)
  end

  test "single-tenant mode puts everyone in one organization" do
    Application.put_env(:starter_kit, :tenancy, :single)
    on_exit(fn -> Application.put_env(:starter_kit, :tenancy, :multi) end)

    first = scope_fixture()
    second = scope_fixture()
    assert first.organization.id == second.organization.id
    assert first.membership.role == :owner
    assert second.membership.role == :member
  end
end
