defmodule Witness.SpanRegistryTest do
  use ExUnit.Case, async: false

  alias Witness.SpanRegistry

  defmodule TestContext do
    use Witness,
      app: :witness,
      prefix: [:test]
  end

  setup do
    # Start the registry
    start_supervised!(TestContext)
    :ok
  end

  # Polls fun/0 up to ~500ms, returning the first non-nil result.
  defp wait_for(fun, retries \\ 50) do
    case fun.() do
      nil when retries > 0 ->
        Process.sleep(10)
        wait_for(fun, retries - 1)

      result ->
        result
    end
  end

  describe "register_span/2" do
    test "stores span ref for current process" do
      span_ref = make_ref()

      assert :ok = SpanRegistry.register_span(TestContext, span_ref)

      # Verify it was stored
      assert {:ok, ^span_ref} = SpanRegistry.lookup_span(TestContext, self())
    end

    test "overwrites previous span ref for same process" do
      first_ref = make_ref()
      second_ref = make_ref()

      SpanRegistry.register_span(TestContext, first_ref)
      SpanRegistry.register_span(TestContext, second_ref)

      # Should have the second ref
      assert {:ok, ^second_ref} = SpanRegistry.lookup_span(TestContext, self())
    end

    test "different processes have independent registrations" do
      parent_ref = make_ref()
      SpanRegistry.register_span(TestContext, parent_ref)

      child_task =
        Task.async(fn ->
          child_ref = make_ref()
          SpanRegistry.register_span(TestContext, child_ref)

          # Parent and child should have different refs
          assert {:ok, ^child_ref} = SpanRegistry.lookup_span(TestContext, self())
          assert {:ok, ^parent_ref} = SpanRegistry.lookup_span(TestContext, Process.get(:"$callers") |> List.first())

          child_ref
        end)

      _child_ref = Task.await(child_task)

      # Parent still has its ref
      assert {:ok, ^parent_ref} = SpanRegistry.lookup_span(TestContext, self())

      # Child process is dead; its entry becomes a tombstone until swept
    end
  end

  describe "unregister_span/2" do
    test "tombstones the entry so it is still findable after the span closes" do
      span_ref = make_ref()
      SpanRegistry.register_span(TestContext, span_ref)

      assert :ok = SpanRegistry.unregister_span(TestContext, span_ref)

      # Tombstone is still visible — out-of-band processors can find the ref
      assert {:ok, ^span_ref} = SpanRegistry.lookup_span(TestContext, self())
    end

    test "tombstone is removed by sweep" do
      span_ref = make_ref()
      SpanRegistry.register_span(TestContext, span_ref)
      SpanRegistry.unregister_span(TestContext, span_ref)

      # Sweep with ttl=0 removes all tombstones immediately
      SpanRegistry.sweep(TestContext, 0)

      assert :error = SpanRegistry.lookup_span(TestContext, self())
    end
  end

  describe "lookup_span/2" do
    test "returns error when no span registered" do
      assert :error = SpanRegistry.lookup_span(TestContext, self())
    end

    test "returns error for unknown process" do
      fake_pid = spawn(fn -> :timer.sleep(:infinity) end)

      assert :error = SpanRegistry.lookup_span(TestContext, fake_pid)

      Process.exit(fake_pid, :kill)
    end

    test "can lookup span from different process" do
      parent_ref = make_ref()
      parent_pid = self()

      SpanRegistry.register_span(TestContext, parent_ref)

      Task.async(fn ->
        # Child can lookup parent's span
        assert {:ok, ^parent_ref} = SpanRegistry.lookup_span(TestContext, parent_pid)
      end)
      |> Task.await()
    end
  end

  describe "lookup_parent_span/1" do
    test "returns error when process has no ancestors" do
      # Main process typically has no $ancestors
      assert :error = SpanRegistry.lookup_parent_span(TestContext)
    end

    test "returns parent span when called from child process" do
      parent_ref = make_ref()
      SpanRegistry.register_span(TestContext, parent_ref)

      Task.async(fn ->
        # Child process should find parent's span
        assert {:ok, ^parent_ref} = SpanRegistry.lookup_parent_span(TestContext)
      end)
      |> Task.await()
    end

    test "returns error when parent has no span registered" do
      # Parent has no span registered

      Task.async(fn ->
        # Child can't find parent span
        assert :error = SpanRegistry.lookup_parent_span(TestContext)
      end)
      |> Task.await()
    end

    test "returns immediate parent span in nested Tasks" do
      parent_ref = make_ref()
      SpanRegistry.register_span(TestContext, parent_ref)

      Task.async(fn ->
        child_ref = make_ref()
        SpanRegistry.register_span(TestContext, child_ref)

        Task.async(fn ->
          # Grandchild should find child's span, not parent's
          assert {:ok, ^child_ref} = SpanRegistry.lookup_parent_span(TestContext)
        end)
        |> Task.await()
      end)
      |> Task.await()
    end
  end

  describe "process death cleanup" do
    test "tombstones ETS entry when process is killed mid-span" do
      span_ref = make_ref()

      pid =
        spawn(fn ->
          SpanRegistry.register_span(TestContext, span_ref)
          Process.sleep(:infinity)
        end)

      # Wait until the ETS entry is visible
      assert {:ok, ^span_ref} =
               wait_for(fn ->
                 case SpanRegistry.lookup_span(TestContext, pid) do
                   {:ok, _} = result -> result
                   _ -> nil
                 end
               end)

      Process.exit(pid, :kill)

      # Entry becomes a tombstone — still findable for out-of-band processors
      assert {:ok, ^span_ref} =
               wait_for(fn ->
                 # The :DOWN message arrives asynchronously; wait for the tombstone insert
                 case :ets.lookup(Module.concat(TestContext, SpanRegistryTable), pid) do
                   [{^pid, _, {:done, _}}] -> SpanRegistry.lookup_span(TestContext, pid)
                   _ -> nil
                 end
               end)

      # Swept away with ttl=0
      SpanRegistry.sweep(TestContext, 0)
      assert :error = SpanRegistry.lookup_span(TestContext, pid)
    end

    test "demonitors cleanly after normal unregister, no monitor leak" do
      span_ref = make_ref()

      pid =
        spawn(fn ->
          SpanRegistry.register_span(TestContext, span_ref)
          SpanRegistry.unregister_span(TestContext, span_ref)
          Process.sleep(:infinity)
        end)

      # Tombstone is visible after normal unregister
      assert {:ok, ^span_ref} =
               wait_for(fn ->
                 case :ets.lookup(Module.concat(TestContext, SpanRegistryTable), pid) do
                   [{^pid, _, {:done, _}}] -> SpanRegistry.lookup_span(TestContext, pid)
                   _ -> nil
                 end
               end)

      Process.exit(pid, :kill)
    end
  end

  describe "ETS table properties" do
    test "table is public and accessible from any process" do
      span_ref = make_ref()
      parent_pid = self()
      SpanRegistry.register_span(TestContext, span_ref)

      # Verify table is accessible from child process
      Task.async(fn ->
        # Direct ETS access should work (public table)
        table_name = Module.concat(TestContext, SpanRegistryTable)
        assert [{_pid, ^span_ref, :active}] = :ets.lookup(table_name, parent_pid)
      end)
      |> Task.await()
    end

    test "supports concurrent reads and writes" do
      # Spawn multiple processes writing concurrently
      tasks =
        for _i <- 1..10 do
          Task.async(fn ->
            ref = make_ref()
            SpanRegistry.register_span(TestContext, ref)
            {:ok, ^ref} = SpanRegistry.lookup_span(TestContext, self())
            ref
          end)
        end

      # All should succeed
      refs = Task.await_many(tasks)
      assert length(refs) == 10
      assert length(Enum.uniq(refs)) == 10
    end
  end
end
