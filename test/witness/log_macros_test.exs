defmodule Witness.LogMacrosTest do
  use ExUnit.Case, async: true

  defmodule TestContext do
    use Witness,
      app: :witness,
      prefix: [:log_macros]
  end

  setup do
    test_pid = self()
    handler_id = make_ref()

    :telemetry.attach_many(
      handler_id,
      Enum.map(Logger.levels(), &[:log_macros, :log, &1]),
      fn event, measurements, _metadata, _ ->
        send(test_pid, {:telemetry_event, event, measurements})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    :ok
  end

  describe "generated log macros from use Witness" do
    test "warning/1 emits [:log, :warning] with message" do
      require TestContext
      TestContext.warning("watch out")

      assert_receive {:telemetry_event, [:log_macros, :log, :warning], measurements}
      assert measurements.message == "watch out"
    end

    test "error/1 emits [:log, :error] with message" do
      require TestContext
      TestContext.error("something broke")

      assert_receive {:telemetry_event, [:log_macros, :log, :error], measurements}
      assert measurements.message == "something broke"
    end

    test "info/1 emits [:log, :info] with message" do
      require TestContext
      TestContext.info("started up")

      assert_receive {:telemetry_event, [:log_macros, :log, :info], measurements}
      assert measurements.message == "started up"
    end

    test "debug/1 emits [:log, :debug] with message" do
      require TestContext
      TestContext.debug("processing item")

      assert_receive {:telemetry_event, [:log_macros, :log, :debug], measurements}
      assert measurements.message == "processing item"
    end

    test "warning/2 passes metadata" do
      require TestContext
      TestContext.warning("disk full", path: "/tmp", usage: "100%")

      assert_receive {:telemetry_event, [:log_macros, :log, :warning], measurements}
      assert measurements.message == "disk full"
      assert measurements.path == "/tmp"
      assert measurements.usage == "100%"
    end
  end
end
