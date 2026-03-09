defmodule Witness.InMemory.SyncTest do
  use ExUnit.Case, async: false

  # Capture repo: uses a persistent_term slot to reach back to the test process.
  defmodule CaptureRepo do
    def insert(event, _opts \\ []) do
      case :persistent_term.get(__MODULE__, nil) do
        nil -> {:ok, event}
        pid -> send(pid, {:inserted, event})
      end

      {:ok, event}
    end
  end

  setup do
    :persistent_term.put(CaptureRepo, self())
    on_exit(fn -> :persistent_term.erase(CaptureRepo) end)
    :ok
  end

  test "forwards new Mnesia write events to configured repo" do
    table = :sync_test_table
    {:ok, pid} = Witness.InMemory.Sync.start_link(repo: CaptureRepo, table: table)

    record = {table, "sha123", ~s({"kind":"obs"}), "test/event", nil}
    send(pid, {:mnesia_table_event, {:write, table, record, [], :activity}})

    assert_receive {:inserted, event}
    assert event.sha == "sha123"
    assert event.data == ~s({"kind":"obs"})
    assert event.message == "test/event"
    assert event.parent == nil

    GenServer.stop(pid)
  end

  test "ignores write events that are updates (have old records)" do
    table = :sync_test_table2
    {:ok, pid} = Witness.InMemory.Sync.start_link(repo: CaptureRepo, table: table)

    old = {table, "sha456", "old_data", "old_message", nil}
    new = {table, "sha456", "new_data", "new_message", nil}
    send(pid, {:mnesia_table_event, {:write, table, new, [old], :activity}})

    refute_receive {:inserted, _}, 50

    GenServer.stop(pid)
  end

  test "ignores events for other tables" do
    table = :sync_test_table3
    {:ok, pid} = Witness.InMemory.Sync.start_link(repo: CaptureRepo, table: table)

    record = {:other_table, "sha789", "data", "message", nil}
    send(pid, {:mnesia_table_event, {:write, :other_table, record, [], :activity}})

    refute_receive {:inserted, _}, 50

    GenServer.stop(pid)
  end
end
