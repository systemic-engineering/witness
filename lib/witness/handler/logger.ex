defmodule Witness.Handler.Logger do
  @moduledoc """
  A handler that logs all telemetry events using Elixir's Logger.

  ## Configuration

  The handler can be configured with a log level (default: `:debug`):

      use Witness,
        handler: [
          {Witness.Handler.Logger, level: :info}
        ]

  ## Log Format

  Events are logged with structured metadata including:
  - `event`: The full event name
  - `measurements`: Event measurements/attributes
  - `metadata`: Event metadata (excluding internal observability metadata)
  - `context`: The observability context

  ## Log Level Selection

  By default, all events are logged at the configured level (`:debug`).

  You can override this by including a `:log_level` key in the event metadata:

      O11y.track_event([:user, :created], %{user_id: 123}, %{log_level: :info})

  Special handling:
  - Events with `:exception` suffix are logged at `:error` level
  - Spans with `{:error, _}` status are logged at `:warning` level
  - Log events (from `Witness.Logger`) use their specified level
  """
  @behaviour Witness.Handler

  require Logger

  alias Witness.Utils

  @impl true
  def handle_event(event_name, measurements, meta, config) do
    {observability_meta, meta} = Utils.pop_enriched_meta(meta)
    {_internal_meta, meta} = Map.split(meta, [:telemetry_span_context, :caller])

    log_level = determine_log_level(event_name, observability_meta, meta, config)

    logger_meta = [
      event: event_name,
      measurements: measurements,
      metadata: meta,
      context: observability_meta[:context]
    ]

    message = format_message(event_name, measurements, meta, observability_meta)

    Logger.log(log_level, message, logger_meta)
  end

  defp determine_log_level(event_name, observability_meta, meta, config) do
    cond do
      # Explicit log level in metadata
      meta[:log_level] ->
        meta[:log_level]

      # Log events from Witness.Logger
      match?([:log, _level, :start], Enum.take(event_name, -3)) ->
        event_name |> Enum.reverse() |> Enum.at(1)

      match?([:log, _level], Enum.take(event_name, -2)) ->
        event_name |> Enum.reverse() |> Enum.at(0)

      # Exception events
      List.last(event_name) == :exception ->
        :error

      # Error status spans
      match?({:error, _}, observability_meta[:status]) ->
        :warning

      # Default from config or :debug
      true ->
        Keyword.get(config, :level, :debug)
    end
  end

  defp format_message(event_name, measurements, meta, observability_meta) do
    event_str = Enum.map_join(event_name, ".", &to_string/1)

    case {List.last(event_name), observability_meta[:status]} do
      {:start, _} ->
        ["[Span Start] ", event_str, format_attributes(measurements, meta)]

      {:stop, status} ->
        ["[Span Stop] ", event_str, format_status(status), format_duration(measurements)]

      {:exception, _} ->
        ["[Span Exception] ", event_str, format_exception(meta)]

      _ ->
        ["[Event] ", event_str, format_attributes(measurements, meta)]
    end
  end

  defp format_attributes(measurements, meta) when map_size(measurements) == 0 and map_size(meta) == 0 do
    ""
  end

  defp format_attributes(measurements, meta) do
    attributes =
      measurements
      |> Map.merge(meta)
      |> Enum.map_join(" ", fn {k, v} -> "#{k}=#{inspect(v)}" end)

    [" | ", attributes]
  end

  defp format_status({:ok, nil}), do: " (ok)"
  defp format_status({:ok, details}), do: [" (ok: ", inspect(details), ")"]
  defp format_status({:error, details}), do: [" (error: ", inspect(details), ")"]
  defp format_status(_), do: ""

  defp format_duration(%{duration: duration}) when is_integer(duration) do
    [" | duration=", format_time(duration)]
  end

  defp format_duration(_), do: ""

  defp format_time(native_time) do
    microseconds = System.convert_time_unit(native_time, :native, :microsecond)

    cond do
      microseconds < 1_000 -> "#{microseconds}µs"
      microseconds < 1_000_000 -> "#{Float.round(microseconds / 1_000, 2)}ms"
      true -> "#{Float.round(microseconds / 1_000_000, 2)}s"
    end
  end

  defp format_exception(%{kind: kind, reason: reason}) do
    [" | ", inspect(kind), ": ", Exception.format_banner(kind, reason)]
  end

  defp format_exception(_), do: ""
end
