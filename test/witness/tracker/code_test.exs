defmodule Witness.Tracker.CodeTest.TestContext do
  use Witness,
    app: :witness,
    prefix: [:test, :code]
end

defmodule Witness.Tracker.CodeTest do
  use ExUnit.Case, async: false

  alias Witness.Tracker.CodeTest.TestContext
  require TestContext

  setup do
    start_supervised!(TestContext)
    :ok
  end

  describe "with_span code paths" do
    test "handles do block syntax" do
      result =
        TestContext.with_span [:test, :span], %{} do
          :result_value
        end

      assert result == :result_value
    end

    test "handles 0-arity function syntax" do
      result =
        TestContext.with_span([:test, :span], %{}, fn ->
          :result_value
        end)

      assert result == :result_value
    end

    test "handles 1-arity function syntax with span modification" do
      result =
        TestContext.with_span([:test, :span], %{}, fn span ->
          Witness.Span.with_result(span, :custom_result)
        end)

      assert result == :custom_result
    end
  end

  describe "track_event" do
    test "emits telemetry event" do
      TestContext.track_event([:test, :event], %{count: 5}, %{meta: "data"})

      # Event was emitted (tracked via telemetry)
    end
  end

  describe "generated functions" do
    test "active_span/0" do
      assert is_nil(TestContext.active_span())
    end

    test "set_active_span/1" do
      span = %Witness.Span{id: make_ref(), context: TestContext, event_name: [:test]}
      TestContext.set_active_span(span)

      assert TestContext.active_span() == span

      TestContext.set_active_span(nil)
    end

    test "add_span_meta/1" do
      TestContext.with_span [:test], %{} do
        assert TestContext.add_span_meta(%{extra: "data"})
      end
    end

    test "set_span_status/1" do
      TestContext.with_span [:test], %{} do
        assert TestContext.set_span_status(:ok)
      end
    end

    test "set_span_status/2" do
      TestContext.with_span [:test], %{} do
        assert TestContext.set_span_status(:error, "failed")
      end
    end
  end

  describe "compile-time validation" do
    test "raises CompileError for dynamic event names in track_event" do
      code = """
      defmodule DynamicEventTest do
        use Witness, app: :witness, prefix: [:test]
        require #{__MODULE__}.TestContext, as: TC

        def test_dynamic do
          event = [:dynamic, :event]
          TC.track_event(event, %{})
        end
      end
      """

      assert_raise CompileError, ~r/Event names need to be a static list of atoms/, fn ->
        Code.compile_string(code)
      end
    end

    test "raises CompileError for non-list event names in with_span" do
      code = """
      defmodule NonListEventTest do
        use Witness, app: :witness, prefix: [:test]
        require #{__MODULE__}.TestContext, as: TC

        def test_non_list do
          TC.with_span :not_a_list, %{} do
            :ok
          end
        end
      end
      """

      assert_raise CompileError, ~r/Event names need to be a static list of atoms/, fn ->
        Code.compile_string(code)
      end
    end

    test "raises CompileError for event names with non-atoms" do
      code = """
      defmodule NonAtomEventTest do
        use Witness, app: :witness, prefix: [:test]
        require #{__MODULE__}.TestContext, as: TC

        def test_non_atom do
          TC.track_event([:valid, "not_atom"], %{})
        end
      end
      """

      assert_raise CompileError, ~r/Event names need to be a static list of atoms/, fn ->
        Code.compile_string(code)
      end
    end

    test "raises CompileError for event names with variables" do
      code = """
      defmodule VariableEventTest do
        use Witness, app: :witness, prefix: [:test]
        require #{__MODULE__}.TestContext, as: TC

        def test_variable do
          suffix = :variable
          TC.with_span([:event, suffix], %{}) do
            :ok
          end
        end
      end
      """

      assert_raise CompileError, ~r/Event names need to be a static list of atoms/, fn ->
        Code.compile_string(code)
      end
    end

    test "accepts valid static event names" do
      code = """
      defmodule ValidEventTest do
        use Witness, app: :witness, prefix: [:test]
        require #{__MODULE__}.TestContext, as: TC

        def test_valid do
          TC.track_event([:valid, :event], %{})
          TC.with_span([:another, :valid, :event], %{}) do
            :ok
          end
        end
      end
      """

      assert [{ValidEventTest, _bytecode}] = Code.compile_string(code)
      :code.delete(ValidEventTest)
      :code.purge(ValidEventTest)
    end
  end
end
