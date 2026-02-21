defmodule Witness.Test do
  @moduledoc """
  Test helpers for Witness observability contexts.

  A drop-in replacement for `ExUnit.CaptureLog` for modules that use
  `Witness.Logger` instead of Elixir's `Logger` directly.
  """

  @doc """
  Captures log events emitted via `Witness.Logger` during the execution of `fun`.

  Attaches telemetry handlers for all Logger levels on the given context's prefix,
  runs `fun`, collects emitted log events, and returns them as a string in the
  format `"[level] message\\n"` — matching `ExUnit.CaptureLog.capture_log/1`
  semantics so it works as a drop-in replacement.

  Only captures log events emitted synchronously in the calling process.
  Events logged from spawned processes may arrive after the capture window closes
  and will be silently missed — the same limitation as `ExUnit.CaptureLog`.

  ## Example

      log = Witness.Test.capture_log(MyApp.Observability, fn ->
        MyModule.do_something()
      end)
      assert log =~ "some warning"

  """
  @spec capture_log(Witness.t(), (() -> any())) :: String.t()
  def capture_log(context, fun) when is_atom(context) and is_function(fun, 0) do
    prefix = context.config()[:prefix]
    ref = make_ref()
    test_pid = self()

    for level <- Logger.levels() do
      :telemetry.attach(
        {__MODULE__, ref, level},
        prefix ++ [:log, level],
        fn _event, measurements, _metadata, _ ->
          send(test_pid, {ref, level, measurements})
        end,
        nil
      )
    end

    try do
      fun.()
    after
      for level <- Logger.levels() do
        :telemetry.detach({__MODULE__, ref, level})
      end
    end

    collect_log_lines(ref, [])
  end

  defp collect_log_lines(ref, acc) do
    receive do
      {^ref, level, %{message: message}} ->
        collect_log_lines(ref, ["[#{level}] #{message}\n" | acc])
    after
      0 -> acc |> Enum.reverse() |> IO.iodata_to_binary()
    end
  end
end
