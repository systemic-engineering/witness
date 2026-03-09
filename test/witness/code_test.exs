defmodule Witness.CodeTest do
  use ExUnit.Case, async: false

  # Defined at module level so hooks fire when this test file compiles.
  defmodule SampleContext do
    use Witness,
      app: :witness,
      prefix: [:code, :test]

    def public_one, do: :ok
    def public_two(_x), do: :ok
    defp private_one, do: :hidden
  end

  describe "__witness__/0 (runtime)" do
    test "is injected into the context module" do
      assert function_exported?(SampleContext, :__witness__, 0)
    end

    test "returns nil when no witness in process dict" do
      assert SampleContext.__witness__() == nil
    end
  end

  describe "__witness_compiled__/0" do
    test "is injected into the context module" do
      assert function_exported?(SampleContext, :__witness_compiled__, 0)
    end

    test "returns a %Witness{} struct" do
      compiled = SampleContext.__witness_compiled__()
      assert %Witness{} = compiled
    end

    test "has the correct module" do
      compiled = SampleContext.__witness_compiled__()
      assert compiled.module == SampleContext
    end

    test "has the configured prefix" do
      compiled = SampleContext.__witness_compiled__()
      assert compiled.prefix == [:code, :test]
    end

    test "has t0 as integer" do
      compiled = SampleContext.__witness_compiled__()
      assert is_integer(compiled.t0)
    end

    test "has accumulated events" do
      compiled = SampleContext.__witness_compiled__()
      assert is_list(compiled.events)
      assert length(compiled.events) > 0
    end

    test "is backward compatible with dot access" do
      compiled = SampleContext.__witness_compiled__()
      assert is_map(compiled)
      assert Map.has_key?(compiled, :t0)
      assert Map.has_key?(compiled, :events)
    end
  end

  describe "compile hooks emit telemetry" do
    setup do
      ref = make_ref()
      on_exit(fn -> :telemetry.detach(ref) end)
      {:ok, ref: ref}
    end

    test "emits :definition events for defined functions", %{ref: ref} do
      :telemetry.attach(
        ref,
        [:witness, :use, :definition],
        fn _, measurements, meta, pid -> send(pid, {:definition, measurements, meta}) end,
        self()
      )

      # Compile a fresh module — unique name so it recompiles each run
      n = System.unique_integer([:positive])

      Code.eval_string("""
      defmodule :"Elixir.Witness.CodeTest.Inline#{n}" do
        use Witness, app: :witness, prefix: [:code, :inline]
        def alpha, do: :ok
        def beta(_x), do: :ok
      end
      """)

      assert_receive {:definition, %{arity: 0}, %{name: :alpha}}
      assert_receive {:definition, %{arity: 1}, %{name: :beta}}
    end

    test "emits :summary event before compile", %{ref: ref} do
      :telemetry.attach(
        ref,
        [:witness, :use, :summary],
        fn _, measurements, meta, pid -> send(pid, {:summary, measurements, meta}) end,
        self()
      )

      n = System.unique_integer([:positive])

      Code.eval_string("""
      defmodule :"Elixir.Witness.CodeTest.Summary#{n}" do
        use Witness, app: :witness, prefix: [:code, :summary]
        def one, do: :ok
        def two, do: :ok
        def three, do: :ok
      end
      """)

      # definitions counts ALL functions including those injected by use Witness
      assert_receive {:summary, %{definitions: n}, _meta}
      assert n >= 3
    end

    test "emits :stop event after compile with duration", %{ref: ref} do
      :telemetry.attach(
        ref,
        [:witness, :use, :stop],
        fn _, measurements, meta, pid -> send(pid, {:stop, measurements, meta}) end,
        self()
      )

      n = System.unique_integer([:positive])

      Code.eval_string("""
      defmodule :"Elixir.Witness.CodeTest.Stop#{n}" do
        use Witness, app: :witness, prefix: [:code, :stop]
      end
      """)

      assert_receive {:stop, measurements, _meta}
      assert is_integer(measurements.duration)
      assert measurements.duration >= 0
      assert is_integer(measurements.bytecode_size)
    end
  end

  describe "setup/0" do
    test "returns :ok regardless of config" do
      assert :ok = Witness.Code.setup()
    end
  end
end
