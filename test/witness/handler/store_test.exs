defmodule Witness.Handler.StoreTest do
  use ExUnit.Case, async: false

  alias Witness.Handler.Store, as: StoreHandler
  alias Witness.Store.Mnesia

  defmodule TestContext do
    use Witness,
      app: :witness,
      prefix: [:handler, :store, :test]
  end

  setup do
    :mnesia.start()

    # Start the Mnesia store for TestContext
    mnesia_config = [context: TestContext]
    {:ok, pid} = Mnesia.start_link(mnesia_config)

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid)

      table = Module.concat(TestContext, WitnessEvents)

      case :mnesia.delete_table(table) do
        {:atomic, :ok} -> :ok
        {:aborted, _} -> :ok
      end
    end)

    {:ok, mnesia_config: mnesia_config}
  end

  describe "behaviour" do
    test "implements Witness.Handler behaviour" do
      assert Code.ensure_loaded?(StoreHandler)
      assert {:handle_event, 4} in StoreHandler.__info__(:functions)
    end

    test "implements child_spec/1" do
      assert Code.ensure_loaded?(StoreHandler)
      assert {:child_spec, 1} in StoreHandler.__info__(:functions)
    end
  end

  describe "handle_event/4" do
    test "delegates to the configured store's store_event/5" do
      handler_config = {Mnesia, context: TestContext}

      StoreHandler.handle_event(
        [:user, :created],
        %{user_id: 42},
        %{source: "test"},
        handler_config
      )

      # Verify event was persisted
      {:ok, events} = Mnesia.list_events(TestContext, [], context: TestContext)
      assert length(events) == 1

      [event] = events
      assert event.event_name == [:user, :created]
      assert event.attributes == %{user_id: 42}
      assert event.meta == %{source: "test"}
    end

    test "stores multiple events through the handler" do
      handler_config = {Mnesia, context: TestContext}

      StoreHandler.handle_event([:event, :one], %{n: 1}, %{}, handler_config)
      StoreHandler.handle_event([:event, :two], %{n: 2}, %{}, handler_config)

      {:ok, events} = Mnesia.list_events(TestContext, [], context: TestContext)
      assert length(events) == 2
    end
  end

  describe "child_spec/1" do
    test "delegates to the configured store's child_spec/1" do
      # child_spec receives the context module, from which it reads store config
      context_config = {Mnesia, context: TestContext}
      spec = StoreHandler.child_spec(context_config)

      assert spec.id == {Mnesia, TestContext}
      assert spec.type == :worker
    end
  end
end
