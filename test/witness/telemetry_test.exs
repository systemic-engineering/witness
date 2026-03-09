defmodule Witness.TelemetryTest do
  use ExUnit.Case, async: false

  alias Witness.Telemetry

  defmodule CaptureRepo do
    def insert(event, _opts \\ []) do
      case :persistent_term.get(__MODULE__, nil) do
        nil -> :ok
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

  describe "attach/2" do
    test "attaches handler that writes to each repo on event" do
      event = [:witness, :telemetry_test, :write]
      :ok = Telemetry.attach(event, [CaptureRepo])

      :telemetry.execute(event, %{duration: 100}, %{module: __MODULE__})

      assert_receive {:inserted, %Witness.Event{} = e}
      assert e.message == "witness/telemetry_test/write"
    end

    test "writes measurements and metadata as JSON data" do
      event = [:witness, :telemetry_test, :data]
      :ok = Telemetry.attach(event, [CaptureRepo])

      :telemetry.execute(event, %{duration: 42}, %{module: MyMod})

      assert_receive {:inserted, %Witness.Event{data: data}}
      parsed = JSON.decode!(data)
      assert parsed["measurements"]["duration"] == 42
      assert parsed["metadata"]["module"] == inspect(MyMod)
    end

    test "calling attach twice is a no-op" do
      event = [:witness, :telemetry_test, :idempotent]
      assert :ok = Telemetry.attach(event, [CaptureRepo])
      assert :ok = Telemetry.attach(event, [CaptureRepo])
    end

    test "empty repos does not attach a handler" do
      event = [:witness, :telemetry_test, :empty]
      :ok = Telemetry.attach(event, [])

      :telemetry.execute(event, %{}, %{})

      refute_receive {:inserted, _}, 50
    end

    test "writes to multiple repos" do
      event = [:witness, :telemetry_test, :multi]
      :ok = Telemetry.attach(event, [CaptureRepo, CaptureRepo])

      :telemetry.execute(event, %{}, %{})

      assert_receive {:inserted, _}
      assert_receive {:inserted, _}
    end
  end
end
