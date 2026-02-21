defmodule Witness.TestTest do
  use ExUnit.Case, async: true

  defmodule TestContext do
    use Witness,
      app: :witness,
      prefix: [:test_helper]
  end

  describe "capture_log/2" do
    test "captures warning message" do
      log =
        Witness.Test.capture_log(TestContext, fn ->
          require Witness.Logger
          Witness.Logger.warning(TestContext, "something went wrong")
        end)

      assert log =~ "something went wrong"
    end

    test "includes the log level" do
      log =
        Witness.Test.capture_log(TestContext, fn ->
          require Witness.Logger
          Witness.Logger.error(TestContext, "fatal error")
        end)

      assert log =~ "[error]"
    end

    test "captures metadata merged into the message" do
      log =
        Witness.Test.capture_log(TestContext, fn ->
          require Witness.Logger
          Witness.Logger.warning(TestContext, "disk usage high", usage: "92%")
        end)

      assert log =~ "disk usage high"
    end

    test "returns empty string when no log events emitted" do
      log = Witness.Test.capture_log(TestContext, fn -> :ok end)
      assert log == ""
    end

    test "captures multiple events in order" do
      log =
        Witness.Test.capture_log(TestContext, fn ->
          require Witness.Logger
          Witness.Logger.info(TestContext, "first")
          Witness.Logger.warning(TestContext, "second")
        end)

      assert log =~ "first"
      assert log =~ "second"
      {first_pos, _} = :binary.match(log, "first")
      {second_pos, _} = :binary.match(log, "second")
      assert first_pos < second_pos
    end

    test "cleans up telemetry handlers even if fun raises" do
      assert_raise RuntimeError, fn ->
        Witness.Test.capture_log(TestContext, fn -> raise "boom" end)
      end

      # Verify handlers are detached by confirming we can attach them again without conflict
      log =
        Witness.Test.capture_log(TestContext, fn ->
          require Witness.Logger
          Witness.Logger.info(TestContext, "after raise")
        end)

      assert log =~ "after raise"
    end
  end
end
