defmodule Witness.WitnessHelpersTest do
  use ExUnit.Case, async: false

  defmodule HelperContext do
    use Witness,
      app: :witness,
      prefix: [:helper, :test]
  end

  setup do
    on_exit(fn -> Process.delete(:__witness__) end)
    :ok
  end

  describe "__witness__/0 (process dict read)" do
    test "returns nil when no witness is set" do
      assert HelperContext.__witness__() == nil
    end

    test "returns the witness after it's been set" do
      witness = %Witness{module: HelperContext, prefix: [:helper, :test]}
      HelperContext.__witness__(witness)
      assert HelperContext.__witness__() == witness
    end
  end

  describe "__witness__/1 with %Witness{} (process dict write)" do
    test "stores witness in process dict" do
      witness = %Witness{module: HelperContext, prefix: [:helper, :test]}
      HelperContext.__witness__(witness)

      assert Process.get(:__witness__) == witness
    end

    test "emits telemetry on write" do
      ref = make_ref()

      :telemetry.attach(
        ref,
        [:witness, :state],
        fn _, _, meta, pid -> send(pid, {:witness_state, meta}) end,
        self()
      )

      witness = %Witness{module: HelperContext, prefix: [:helper, :test]}
      HelperContext.__witness__(witness)

      assert_receive {:witness_state, %{witness: ^witness}}

      :telemetry.detach(ref)
    end
  end

  describe "__witness__/0 round-trip" do
    test "write then read returns the same struct" do
      witness = %Witness{
        module: HelperContext,
        prefix: [:helper, :test],
        t0: 42,
        events: [{:def, :foo, 0}]
      }

      HelperContext.__witness__(witness)
      read_back = HelperContext.__witness__()

      assert read_back == witness
      assert read_back.t0 == 42
      assert read_back.events == [{:def, :foo, 0}]
    end
  end
end
