defmodule Witness.Store.MnesiaTest do
  use ExUnit.Case, async: false

  alias Witness.Store.Mnesia

  # Each test gets its own context module to avoid table name collisions.
  # The store config is passed directly to Mnesia functions, not through
  # `use Witness` (that integration is tested separately in Step 5).
  defmodule TestContext do
    use Witness,
      app: :witness,
      prefix: [:store, :mnesia, :test]
  end

  defmodule IsolationContextA do
    use Witness,
      app: :witness,
      prefix: [:store, :mnesia, :iso_a]
  end

  defmodule IsolationContextB do
    use Witness,
      app: :witness,
      prefix: [:store, :mnesia, :iso_b]
  end

  defmodule DiscContext do
    use Witness,
      app: :witness,
      prefix: [:store, :mnesia, :disc]
  end

  setup do
    # Ensure Mnesia is started
    :mnesia.start()

    on_exit(fn ->
      # Clean up all test tables
      for context <- [TestContext, IsolationContextA, IsolationContextB, DiscContext] do
        table = Module.concat(context, WitnessEvents)

        case :mnesia.delete_table(table) do
          {:atomic, :ok} -> :ok
          {:aborted, _} -> :ok
        end
      end
    end)

    :ok
  end

  describe "table creation on init" do
    test "creates a Mnesia table for the context" do
      config = [context: TestContext]
      {:ok, pid} = Mnesia.start_link(config)

      table = Module.concat(TestContext, WitnessEvents)
      assert :mnesia.table_info(table, :type) == :ordered_set
      assert :mnesia.table_info(table, :ram_copies) == [node()]

      GenServer.stop(pid)
    end

    test "table uses ordered_set for chronological ordering" do
      config = [context: TestContext]
      {:ok, pid} = Mnesia.start_link(config)

      table = Module.concat(TestContext, WitnessEvents)
      assert :mnesia.table_info(table, :type) == :ordered_set

      GenServer.stop(pid)
    end
  end

  describe "store_event/5" do
    test "writes records to the Mnesia table" do
      config = [context: TestContext]
      {:ok, pid} = Mnesia.start_link(config)

      event_name = [:user, :created]
      attributes = %{user_id: 123}
      meta = %{source: "test"}

      assert :ok = Mnesia.store_event(event_name, attributes, meta, TestContext, config)

      # Verify the record exists in Mnesia
      {:ok, events} = Mnesia.list_events(TestContext, [], config)
      assert length(events) == 1

      [event] = events
      assert event.event_name == [:user, :created]
      assert event.attributes == %{user_id: 123}
      assert event.meta == %{source: "test"}

      GenServer.stop(pid)
    end

    test "stores multiple events" do
      config = [context: TestContext]
      {:ok, pid} = Mnesia.start_link(config)

      :ok = Mnesia.store_event([:event, :one], %{n: 1}, %{}, TestContext, config)
      :ok = Mnesia.store_event([:event, :two], %{n: 2}, %{}, TestContext, config)
      :ok = Mnesia.store_event([:event, :three], %{n: 3}, %{}, TestContext, config)

      {:ok, events} = Mnesia.list_events(TestContext, [], config)
      assert length(events) == 3

      GenServer.stop(pid)
    end
  end

  describe "list_events/3" do
    test "returns events in chronological order" do
      config = [context: TestContext]
      {:ok, pid} = Mnesia.start_link(config)

      :ok = Mnesia.store_event([:first], %{order: 1}, %{}, TestContext, config)
      # Small sleep to ensure distinct timestamps
      Process.sleep(1)
      :ok = Mnesia.store_event([:second], %{order: 2}, %{}, TestContext, config)
      Process.sleep(1)
      :ok = Mnesia.store_event([:third], %{order: 3}, %{}, TestContext, config)

      {:ok, events} = Mnesia.list_events(TestContext, [], config)
      orders = Enum.map(events, & &1.attributes.order)
      assert orders == [1, 2, 3]

      GenServer.stop(pid)
    end

    test ":after filter excludes events before the given timestamp" do
      config = [context: TestContext]
      {:ok, pid} = Mnesia.start_link(config)

      :ok = Mnesia.store_event([:old], %{n: 1}, %{}, TestContext, config)
      Process.sleep(2)

      cutoff = System.system_time(:microsecond)
      Process.sleep(2)

      :ok = Mnesia.store_event([:new], %{n: 2}, %{}, TestContext, config)

      {:ok, events} = Mnesia.list_events(TestContext, [after: cutoff], config)
      assert length(events) == 1
      assert hd(events).event_name == [:new]

      GenServer.stop(pid)
    end

    test ":before filter excludes events after the given timestamp" do
      config = [context: TestContext]
      {:ok, pid} = Mnesia.start_link(config)

      :ok = Mnesia.store_event([:old], %{n: 1}, %{}, TestContext, config)
      Process.sleep(2)

      cutoff = System.system_time(:microsecond)
      Process.sleep(2)

      :ok = Mnesia.store_event([:new], %{n: 2}, %{}, TestContext, config)

      {:ok, events} = Mnesia.list_events(TestContext, [before: cutoff], config)
      assert length(events) == 1
      assert hd(events).event_name == [:old]

      GenServer.stop(pid)
    end

    test ":limit constrains the number of returned events" do
      config = [context: TestContext]
      {:ok, pid} = Mnesia.start_link(config)

      for i <- 1..5 do
        :ok = Mnesia.store_event([:event], %{n: i}, %{}, TestContext, config)
        Process.sleep(1)
      end

      {:ok, events} = Mnesia.list_events(TestContext, [limit: 3], config)
      assert length(events) == 3

      # Should return the first 3 chronologically
      ns = Enum.map(events, & &1.attributes.n)
      assert ns == [1, 2, 3]

      GenServer.stop(pid)
    end

    test ":event_name filter returns only matching events" do
      config = [context: TestContext]
      {:ok, pid} = Mnesia.start_link(config)

      :ok = Mnesia.store_event([:user, :created], %{id: 1}, %{}, TestContext, config)
      :ok = Mnesia.store_event([:order, :placed], %{id: 2}, %{}, TestContext, config)
      :ok = Mnesia.store_event([:user, :created], %{id: 3}, %{}, TestContext, config)

      {:ok, events} = Mnesia.list_events(TestContext, [event_name: [:user, :created]], config)
      assert length(events) == 2
      assert Enum.all?(events, &(&1.event_name == [:user, :created]))

      GenServer.stop(pid)
    end

    test "combined filters work together" do
      config = [context: TestContext]
      {:ok, pid} = Mnesia.start_link(config)

      :ok = Mnesia.store_event([:user, :created], %{n: 1}, %{}, TestContext, config)
      Process.sleep(2)

      cutoff = System.system_time(:microsecond)
      Process.sleep(2)

      :ok = Mnesia.store_event([:user, :created], %{n: 2}, %{}, TestContext, config)
      Process.sleep(1)
      :ok = Mnesia.store_event([:order, :placed], %{n: 3}, %{}, TestContext, config)
      Process.sleep(1)
      :ok = Mnesia.store_event([:user, :created], %{n: 4}, %{}, TestContext, config)

      {:ok, events} =
        Mnesia.list_events(TestContext, [after: cutoff, event_name: [:user, :created], limit: 1], config)

      assert length(events) == 1
      assert hd(events).attributes.n == 2

      GenServer.stop(pid)
    end

    test "returns empty list when no events match" do
      config = [context: TestContext]
      {:ok, pid} = Mnesia.start_link(config)

      {:ok, events} = Mnesia.list_events(TestContext, [], config)
      assert events == []

      GenServer.stop(pid)
    end
  end

  describe "context isolation" do
    test "events in one context are not visible in another" do
      config_a = [context: IsolationContextA]
      config_b = [context: IsolationContextB]

      {:ok, pid_a} = Mnesia.start_link(config_a)
      {:ok, pid_b} = Mnesia.start_link(config_b)

      :ok = Mnesia.store_event([:only_in_a], %{ctx: :a}, %{}, IsolationContextA, config_a)
      :ok = Mnesia.store_event([:only_in_b], %{ctx: :b}, %{}, IsolationContextB, config_b)

      {:ok, events_a} = Mnesia.list_events(IsolationContextA, [], config_a)
      {:ok, events_b} = Mnesia.list_events(IsolationContextB, [], config_b)

      assert length(events_a) == 1
      assert hd(events_a).event_name == [:only_in_a]

      assert length(events_b) == 1
      assert hd(events_b).event_name == [:only_in_b]

      GenServer.stop(pid_a)
      GenServer.stop(pid_b)
    end
  end

  describe "disc_copies configuration" do
    test "creates table with disc_copies when configured" do
      config = [context: DiscContext, storage_type: :disc_copies]
      {:ok, pid} = Mnesia.start_link(config)

      table = Module.concat(DiscContext, WitnessEvents)
      assert :mnesia.table_info(table, :disc_copies) == [node()]

      GenServer.stop(pid)
    end
  end

  describe "child_spec/1" do
    test "returns a valid child spec" do
      config = [context: TestContext]
      spec = Mnesia.child_spec(config)

      assert spec.id == {Mnesia, TestContext}
      assert spec.type == :worker
      assert {Mnesia, :start_link, [^config]} = spec.start
    end
  end
end
