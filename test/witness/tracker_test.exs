defmodule Witness.TrackerTest do
  use ExUnit.Case, async: false

  require Witness.Tracker, as: Tracker

  alias Witness.Span

  defmodule TestContext do
    use Witness,
      app: :witness,
      prefix: [:test, :tracker]
  end

  defmodule DirectMacroUser do
    require Witness.Tracker, as: Tracker
    alias Witness.TrackerTest.TestContext

    def use_track_event_macro do
      Tracker.track_event(TestContext, [:direct, :macro, :event], %{data: "test"})
    end
  end

  setup do
    start_supervised!(TestContext)
    :ok
  end

  describe "active_span/1" do
    test "returns nil when no span is active" do
      assert Tracker.active_span(TestContext) == nil
    end

    test "returns the active span when set" do
      span = %Span{id: make_ref(), context: TestContext, event_name: [:test]}
      Tracker.set_active_span(TestContext, span)

      assert Tracker.active_span(TestContext) == span

      # Cleanup
      Tracker.clear_active_span(TestContext)
    end
  end

  describe "set_active_span/2" do
    test "sets the active span" do
      span = %Span{id: make_ref(), context: TestContext, event_name: [:test]}
      Tracker.set_active_span(TestContext, span)

      assert Tracker.active_span(TestContext) == span

      # Cleanup
      Tracker.clear_active_span(TestContext)
    end

    test "setting nil clears the active span" do
      span = %Span{id: make_ref(), context: TestContext, event_name: [:test]}
      Tracker.set_active_span(TestContext, span)

      assert Tracker.active_span(TestContext) == span

      # Set to nil
      Tracker.set_active_span(TestContext, nil)

      assert Tracker.active_span(TestContext) == nil
    end
  end

  describe "clear_active_span/1" do
    test "clears the active span" do
      span = %Span{id: make_ref(), context: TestContext, event_name: [:test]}
      Tracker.set_active_span(TestContext, span)

      assert Tracker.active_span(TestContext) == span

      result = Tracker.clear_active_span(TestContext)

      assert result == span
      assert Tracker.active_span(TestContext) == nil
    end

    test "returns nil when no span was active" do
      result = Tracker.clear_active_span(TestContext)
      assert result == nil
    end
  end

  describe "add_span_meta/2" do
    test "adds metadata to active span" do
      Tracker.with_span TestContext, [:test, :span], %{} do
        result = Tracker.add_span_meta(TestContext, %{extra: "metadata"})

        assert result == true

        span = Tracker.active_span(TestContext)
        assert span.meta.extra == "metadata"
      end
    end

    test "returns false when no span is active" do
      result = Tracker.add_span_meta(TestContext, %{extra: "metadata"})
      assert result == false
    end
  end

  describe "set_span_status/3" do
    test "sets status of active span" do
      Tracker.with_span TestContext, [:test, :span], %{} do
        result = Tracker.set_span_status(TestContext, :ok, "completed")

        assert result == true

        span = Tracker.active_span(TestContext)
        assert span.status == {:ok, "completed"}
      end
    end

    test "sets status with default nil details" do
      Tracker.with_span TestContext, [:test, :span], %{} do
        result = Tracker.set_span_status(TestContext, :error)

        assert result == true

        span = Tracker.active_span(TestContext)
        assert span.status == {:error, nil}
      end
    end

    test "returns false when no span is active" do
      result = Tracker.set_span_status(TestContext, :ok)
      assert result == false
    end
  end

  describe "set_span_status/2 with result tuples" do
    test "sets ok status from {:ok} tuple" do
      Tracker.with_span TestContext, [:test, :span], %{} do
        result = Tracker.set_span_status(TestContext, {:ok})

        assert result == true

        span = Tracker.active_span(TestContext)
        assert span.status == {:ok, nil}
      end
    end

    test "sets error status from {:error, reason} tuple" do
      Tracker.with_span TestContext, [:test, :span], %{} do
        result = Tracker.set_span_status(TestContext, {:error, :timeout})

        assert result == true

        span = Tracker.active_span(TestContext)
        assert span.status == {:error, :timeout}
      end
    end

    test "returns false when no span is active" do
      result = Tracker.set_span_status(TestContext, {:error, :no_span})
      assert result == false
    end
  end

  describe "_with_span/4 with 0-arity function" do
    test "converts 0-arity function to 1-arity" do
      result =
        Tracker._with_span(TestContext, [:test, :span], %{}, fn ->
          :my_result
        end)

      assert result == :my_result
    end
  end

  describe "track_event/4 macro" do
    test "generates code to track event when called directly" do
      # This test exercises the macro path directly (line 86 in tracker.ex)
      # The DirectMacroUser module was compiled with a direct call to the macro
      assert DirectMacroUser.use_track_event_macro() == :ok
    end
  end
end
