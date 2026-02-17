defmodule Witness.HandlerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Witness.Handler

  defmodule TestHandler do
    @behaviour Witness.Handler

    @impl true
    def handle_event(_event, _measurements, _meta, _config) do
      :ok
    end
  end

  defmodule TestContext do
    use Witness,
      app: :witness,
      prefix: [:test, :handler]
  end

  # Create a mock source that implements the Source behaviour
  defmodule MockSource do
    @behaviour Witness.Source

    @impl true
    def __observable__ do
      %{
        context: TestContext,
        events: [[:test, :event, :one], [:test, :event, :two]]
      }
    end
  end

  defmodule ContextWithExtraEvents do
    use Witness,
      app: :witness,
      prefix: [:test, :extras],
      extra_events: [[:extra, :event]]
  end

  defmodule MockSourceWithExtras do
    @behaviour Witness.Source

    @impl true
    def __observable__ do
      %{
        context: ContextWithExtraEvents,
        events: [[:test, :event]]
      }
    end
  end

  defmodule ContextWithSources do
    use Witness,
      app: :witness,
      prefix: [:test, :with_sources],
      sources: [__MODULE__.MockSource]
  end

  defmodule ContextWithSources.MockSource do
    @behaviour Witness.Source

    @impl true
    def __observable__ do
      %{
        context: Witness.HandlerTest.ContextWithSources,
        events: [[:test, :with_sources, :event, :one], [:test, :with_sources, :event, :two]]
      }
    end
  end

  defmodule ContextWithInvalidApp do
    use Witness,
      app: :nonexistent_app_12345,
      prefix: [:test, :invalid]
  end

  setup do
    start_supervised!(TestContext)
    :ok
  end

  describe "attach_to_context/3" do
    test "logs warning when context has no sources" do
      handler_id = make_ref()

      log =
        capture_log(fn ->
          result = Handler.attach_to_context(handler_id, {TestHandler, :config}, TestContext)
          assert result == :ok
        end)

      assert log =~ "Will attach handler to all events in context."
      assert log =~ "Did not attach handler as the given context has no sources."
    end

    test "attaches handler without config (uses context as config)" do
      handler_id = make_ref()

      log =
        capture_log(fn ->
          result = Handler.attach_to_context(handler_id, TestHandler, TestContext)
          assert result == :ok
        end)

      assert log =~ "Will attach handler to all events in context."
      assert log =~ "Did not attach handler as the given context has no sources."
    end

    test "attaches handler when context has sources" do
      handler_id = make_ref()

      log =
        capture_log([metadata: [:number_of_events]], fn ->
          result =
            Handler.attach_to_context(handler_id, {TestHandler, :config}, ContextWithSources)

          assert result == :ok
        end)

      assert log =~ "Will attach handler to all events in context."
      assert log =~ "Did attach handler to events."
      assert log =~ "number_of_events=2"

      # Cleanup
      :telemetry.detach(handler_id)
    end

    test "returns error when sources_in fails with clear error message" do
      handler_id = make_ref()

      log =
        capture_log(fn ->
          result =
            Handler.attach_to_context(handler_id, {TestHandler, :config}, ContextWithInvalidApp)

          assert {:error, {:unknown_app, :nonexistent_app_12345}} = result
        end)

      assert log =~ "Will attach handler to all events in context."

      # Better error reporting - explains what's wrong and how to fix it
      assert log =~ "Unknown OTP application"
      assert log =~ ":nonexistent_app_12345"
      assert log =~ "not loaded or does not exist"
      assert log =~ "Application.ensure_all_started"
    end
  end

  describe "attach/3" do
    test "attaches handler with config to specific events" do
      handler_id = make_ref()
      events = [[:test, :event, :one], [:test, :event, :two]]

      log =
        capture_log([metadata: [:number_of_events]], fn ->
          result = Handler.attach(handler_id, {TestHandler, :my_config}, events)
          assert result == :ok
        end)

      assert log =~ "Did attach handler to events."
      assert log =~ "number_of_events=2"

      # Cleanup
      :telemetry.detach(handler_id)
    end

    test "attaches handler without config" do
      handler_id = make_ref()
      events = [[:test, :event]]

      log =
        capture_log(fn ->
          result = Handler.attach(handler_id, TestHandler, events)
          assert result == :ok
        end)

      assert log =~ "Did attach handler to events."

      # Cleanup
      :telemetry.detach(handler_id)
    end

    test "raises when handler module doesn't have handle_event/4" do
      defmodule InvalidHandler do
        # No handle_event/4 implementation
      end

      handler_id = make_ref()
      events = [[:test, :event]]

      assert_raise ArgumentError,
                   ~r/expected a module with a handle_event\/4 function/,
                   fn ->
                     Handler.attach(handler_id, {InvalidHandler, :config}, events)
                   end
    end

    test "returns :ok immediately for empty event list" do
      handler_id = make_ref()

      result = Handler.attach(handler_id, {TestHandler, :config}, [])
      assert result == :ok
    end

    test "returns error when handler already attached" do
      handler_id = make_ref()
      events = [[:test, :duplicate, :event]]

      # Attach once
      capture_log(fn ->
        assert :ok = Handler.attach(handler_id, {TestHandler, :config}, events)
      end)

      # Try to attach again with same handler_id
      log =
        capture_log(fn ->
          result = Handler.attach(handler_id, {TestHandler, :config}, events)
          assert {:error, :already_exists} = result
        end)

      assert log =~ "Did not attach handler to events; a handler with this ID is already attached."

      # Cleanup
      :telemetry.detach(handler_id)
    end
  end

  describe "behaviour validation" do
    test "TestHandler implements the Handler behaviour" do
      assert function_exported?(TestHandler, :handle_event, 4)
      assert {:behaviour, [Witness.Handler]} in TestHandler.__info__(:attributes)
    end
  end
end
