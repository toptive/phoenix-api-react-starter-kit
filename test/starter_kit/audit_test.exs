defmodule StarterKit.AuditTest do
  use StarterKit.DataCase, async: true

  alias StarterKit.Audit
  alias StarterKit.Audit.AuditEvent

  test "records events and the database refuses to change them" do
    user = user_fixture()
    {:ok, event} = Audit.record("user.tested", actor: user, subject: user, metadata: %{kind: :demo})
    assert event.metadata == %{"kind" => "demo"}

    assert_raise Postgrex.Error, ~r/append-only/, fn ->
      event |> Ecto.Changeset.change(action: "tampered") |> Repo.update()
    end

    assert_raise Postgrex.Error, ~r/append-only/, fn -> Repo.delete(event) end
    assert Repo.get!(AuditEvent, event.id).action == "user.tested"
  end

  test "events take the request IP unless one is given" do
    user = user_fixture()
    {:ok, without} = Audit.record("user.tested", actor: user)
    assert without.ip_address == nil

    :ok = Audit.put_request_ip("203.0.113.7")
    {:ok, from_request} = Audit.record("user.tested", actor: user)
    {:ok, explicit} = Audit.record("user.tested", actor: user, ip_address: "198.51.100.1")

    assert from_request.ip_address == "203.0.113.7"
    assert explicit.ip_address == "198.51.100.1"
  end
end
