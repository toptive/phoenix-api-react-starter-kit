defmodule StarterKit.PlatformTest do
  use StarterKit.DataCase, async: true

  alias StarterKit.{AI, Analytics}

  describe "Analytics" do
    test "tracks catalogued events with allowed properties only" do
      Analytics.track("user_signed_in", %{id: "u1"}, %{method: "password", secret: "x"})

      assert_received {:analytics,
                       %{
                         event: "user_signed_in",
                         distinct_id: "u1",
                         properties: %{"method" => "password"}
                       }}
    end

    test "an event without a user is anonymous: a random id per event, no person profile" do
      Analytics.track("user_signed_in", nil, %{method: "password"})
      Analytics.track("user_signed_in", nil, %{method: "password"})

      assert_received {:analytics, %{distinct_id: first, properties: props}}
      assert_received {:analytics, %{distinct_id: second}}
      assert {:ok, _} = Ecto.UUID.cast(first)
      assert first != second
      assert props == %{"method" => "password", "$process_person_profile" => false}
    end

    test "raises on unknown events in dev/test" do
      assert_raise ArgumentError, fn -> Analytics.track("made_up", nil) end
    end

    test "typed properties: a value that breaks its rule is dropped" do
      Analytics.track("checkout_started", %{id: "u1"}, %{
        plan: "pro",
        interval: "week",
        mode: :live
      })

      assert_received {:analytics, %{properties: %{"plan" => "pro", "mode" => "live"} = props}}
      refute Map.has_key?(props, "interval")
    end

    test "track_after_commit/4 tracks a committed write only and returns the result" do
      assert {:ok, :saved} =
               Analytics.track_after_commit({:ok, :saved}, "onboarding_completed", %{id: "u1"}, %{
                 skipped: true
               })

      assert_received {:analytics,
                       %{event: "onboarding_completed", properties: %{"skipped" => true}}}

      assert {:error, :invalid} =
               Analytics.track_after_commit({:error, :invalid}, "onboarding_completed", nil)

      refute_received {:analytics, _}
    end

    test "an unknown event from the client is ignored, never raised" do
      assert :ignored = Analytics.track("made_up", nil, %{}, client: true)
    end

    test "ignores server-only events sent by the client" do
      assert :ignored = Analytics.track("user_signed_in", nil, %{}, client: true)
    end
  end

  describe "AI" do
    test "chat goes to OpenRouter" do
      Process.put(:ai_response, {:ok, %{"choices" => [%{"message" => %{"content" => "hi"}}]}})
      assert {:ok, "hi"} = AI.chat([%{role: "user", content: "hello"}])
      assert_received {:ai_request, "https://openrouter.ai/api/v1/chat/completions", %{model: _}}
    end
  end
end
