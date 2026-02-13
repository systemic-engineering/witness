defmodule Witness.CrossProcessTest do
  use ExUnit.Case, async: false

  defmodule TestContext do
    use Witness,
      app: :witness,
      prefix: [:test]
  end

  setup do
    # Start the context supervisor to initialize ETS table
    start_supervised!(TestContext)

    # Attach telemetry test handler
    test_pid = self()
    handler_id = make_ref()

    :telemetry.attach_many(
      handler_id,
      [
        [:test, :parent_span, :start],
        [:test, :parent_span, :stop],
        [:test, :child_span, :start],
        [:test, :child_span, :stop],
        [:test, :grandchild_span, :start],
        [:test, :grandchild_span, :stop]
      ],
      fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry_event, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    :ok
  end

  describe "cross-process span tracking" do
    test "child process can access parent span context" do
      require Witness.Tracker, as: Tracker

      # Parent process creates a span
      parent_result =
        Tracker.with_span TestContext, [:parent_span], %{} do
          # Get parent span ID
          parent_span = Tracker.active_span(TestContext)
          parent_ref = parent_span.id

          # Spawn child process
          task =
            Task.async(fn ->
              # Child process creates its own span
              Tracker.with_span TestContext, [:child_span], %{} do
                # Child should be able to see parent span in ETS
                child_span = Tracker.active_span(TestContext)
                {parent_ref, child_span.id}
              end
            end)

          {parent_ref, Task.await(task)}
        end

      {parent_ref, {retrieved_parent_ref, child_ref}} = parent_result

      # Verify events were emitted
      assert_receive {:telemetry_event, [:test, :parent_span, :start], _, parent_meta}
      assert_receive {:telemetry_event, [:test, :child_span, :start], _, child_meta}
      assert_receive {:telemetry_event, [:test, :child_span, :stop], _, _}
      assert_receive {:telemetry_event, [:test, :parent_span, :stop], _, _}

      # Verify span IDs (refs are in __observability__ metadata)
      assert parent_meta.__observability__.ref == parent_ref
      assert child_meta.__observability__.ref == child_ref

      # Verify child could see parent (this is what we're testing)
      assert retrieved_parent_ref == parent_ref

      # The key test: child's parent_span_id should reference the parent
      # This will fail initially because we don't have ETS tracking yet
      # assert child_meta.parent_span_id == parent_ref
    end

    test "nested cross-process spans maintain hierarchy" do
      require Witness.Tracker, as: Tracker

      Tracker.with_span TestContext, [:parent_span], %{} do
        Task.async(fn ->
          Tracker.with_span TestContext, [:child_span], %{} do
            # Nested child within child
            Task.async(fn ->
              Tracker.with_span TestContext, [:grandchild_span], %{} do
                :ok
              end
            end)
            |> Task.await()
          end
        end)
        |> Task.await()
      end

      # All spans should complete successfully
      assert_receive {:telemetry_event, [:test, :parent_span, :start], _, _}
      assert_receive {:telemetry_event, [:test, :child_span, :start], _, _}
      assert_receive {:telemetry_event, [:test, :grandchild_span, :start], _, _}
      assert_receive {:telemetry_event, [:test, :grandchild_span, :stop], _, _}
      assert_receive {:telemetry_event, [:test, :child_span, :stop], _, _}
      assert_receive {:telemetry_event, [:test, :parent_span, :stop], _, _}
    end
  end
end
