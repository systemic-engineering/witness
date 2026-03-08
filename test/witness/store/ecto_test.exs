defmodule Witness.Store.EctoTest do
  use ExUnit.Case, async: false

  alias Witness.Store.Ecto, as: EctoStore

  # Test repo — uses fragmentation's ETS adapter for content-addressed storage
  defmodule TestRepo do
    use Ecto.Repo,
      otp_app: :witness,
      adapter: Fragmentation.Store.ETS
  end

  defmodule TestContext do
    use Witness,
      app: :witness,
      prefix: [:store, :ecto, :test]
  end

  setup do
    start_supervised!(TestRepo)

    try do
      :ets.delete_all_objects(:witness)
    rescue
      ArgumentError -> :ok
    end

    :ok
  end

  describe "store_event/5" do
    test "stores an event via the configured Repo" do
      config = [context: TestContext, repo: TestRepo]

      assert :ok =
               EctoStore.store_event(
                 [:actor, :witnessed],
                 %{document: "abc123"},
                 %{source: "test"},
                 TestContext,
                 config
               )
    end

    test "stored event is retrievable by SHA" do
      config = [context: TestContext, repo: TestRepo]

      :ok =
        EctoStore.store_event(
          [:actor, :witnessed],
          %{document: "abc123"},
          %{source: "test"},
          TestContext,
          config
        )

      {:ok, [event]} = EctoStore.list_events(TestContext, [], config)
      assert event.sha != nil
      assert is_binary(event.sha)
    end

    test "event data contains event_name, attributes, and meta" do
      config = [context: TestContext, repo: TestRepo]
      attributes = %{document: "sha256"}
      meta = %{source: "integration"}

      :ok = EctoStore.store_event([:actor, :witnessed], attributes, meta, TestContext, config)

      {:ok, [event]} = EctoStore.list_events(TestContext, [], config)
      decoded = JSON.decode!(event.data)
      assert decoded["event_name"] == ["actor", "witnessed"]
      assert decoded["attributes"]["document"] == "sha256"
      assert decoded["meta"]["source"] == "integration"
    end

    test "message carries the witness namespace path" do
      config = [context: TestContext, repo: TestRepo]

      :ok =
        EctoStore.store_event(
          [:actor, :witnessed],
          %{document: "abc"},
          %{},
          TestContext,
          config
        )

      {:ok, [event]} = EctoStore.list_events(TestContext, [], config)
      assert event.message == "store/ecto/test/actor/witnessed"
    end

    test "each event gets a unique content-addressed SHA" do
      config = [context: TestContext, repo: TestRepo]

      :ok = EctoStore.store_event([:event, :one], %{n: 1}, %{}, TestContext, config)
      Process.sleep(1)
      :ok = EctoStore.store_event([:event, :two], %{n: 2}, %{}, TestContext, config)

      {:ok, events} = EctoStore.list_events(TestContext, [], config)
      assert length(events) == 2

      shas = Enum.map(events, & &1.sha)
      assert length(Enum.uniq(shas)) == 2
    end
  end

  describe "list_events/3" do
    test "returns empty list when no events exist" do
      config = [context: TestContext, repo: TestRepo]

      {:ok, events} = EctoStore.list_events(TestContext, [], config)
      assert events == []
    end
  end

  describe "child_spec/1" do
    test "returns a no-op child spec (Repo is supervised elsewhere)" do
      config = [context: TestContext, repo: TestRepo]
      spec = EctoStore.child_spec(config)

      assert spec.id == {EctoStore, TestContext}
      assert spec.type == :worker
    end
  end
end
