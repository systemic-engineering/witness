defmodule Witness.Handler.OpenTelemetry do
  @moduledoc false
  @behaviour Witness.Handler

  alias OpenTelemetry, as: Otel
  alias OpentelemetryTelemetry, as: OtelTranslator
  alias Witness.Utils

  require Logger

  @tracer_id __MODULE__
  @telemetry_meta_keys [:telemetry_span_context]

  @impl true
  def handle_event(event_name, measurements, meta, _config) do
    {observability_meta, meta} = Utils.pop_enriched_meta(meta)
    {telemetry_meta, meta} = Map.split(meta, @telemetry_meta_keys)

    case map_to_otel(event_name) do
      {:event, name} ->
        Logger.debug("Will attach event to OpenTelemetry.Span.",
          event: name,
          event_attributes: measurements,
          event_meta: meta
        )

        event_attributes =
          measurements
          |> Map.put(:__meta__, meta)
          |> Utils.flatten_map(&to_otel_attribute/1)

        if !Otel.Tracer.add_event(name, event_attributes) do
          Logger.info("Did not add observability event to OpenTelemetry.Span as none is active.",
            event: name,
            event_attributes: measurements,
            event_meta: meta
          )
        end

        :ignored

      {:span, :start, name} ->
        start_time = measurements[:monotonic_time] || :erlang.monotonic_time()
        span_attributes = Utils.flatten_map(meta, &to_otel_attribute/1)

        Logger.debug("Will start OpenTelemetry.Span.",
          span: name,
          span_attributes: span_attributes
        )

        OtelTranslator.start_telemetry_span(@tracer_id, name, telemetry_meta, %{
          attributes: span_attributes,
          links: [],
          is_recording: true,
          start_time: start_time,
          kind: meta[:kind] || :internal
        })

      {:span, :stop, name} ->
        span_attributes = Utils.flatten_map(meta, &to_otel_attribute/1)

        Logger.debug("Will stop OpenTelemetry.Span.",
          span: name,
          span_attributes: span_attributes
        )

        with_current_span(telemetry_meta, fn span ->
          Otel.Span.set_status(span, to_otel_status(observability_meta[:status]))
          Otel.Span.set_attributes(span, span_attributes)
        end)

        OtelTranslator.end_telemetry_span(@tracer_id, telemetry_meta)

      {:span, :exception, name} ->
        %{reason: reason, stacktrace: stacktrace, kind: kind} = meta

        span_attributes =
          meta
          |> Map.drop([:kind, :reason, :stacktrace])
          |> Utils.flatten_map(&to_otel_attribute/1)

        Logger.debug("Will record an exception for an OpenTelemetry.Span and stop it.",
          span: name,
          span_attributes: span_attributes,
          span_exception: reason
        )

        with_current_span(telemetry_meta, fn span ->
          Otel.Span.record_exception(span, reason, stacktrace, kind: kind)
          Otel.Span.set_status(span, to_otel_status({:error, reason}))
          Otel.Span.set_attributes(span, span_attributes)
        end)

        OtelTranslator.end_telemetry_span(@tracer_id, telemetry_meta)
    end
  end

  defp map_to_otel(mapped \\ [], original)

  @span_events [:start, :stop, :exception]
  defp map_to_otel(mapped, [event]) when event in @span_events do
    {:span, event, otel_name(mapped)}
  end

  defp map_to_otel(mapped, []) do
    {:event, otel_name(mapped)}
  end

  defp map_to_otel(mapped, [part | rest]) do
    map_to_otel([part | mapped], rest)
  end

  defp otel_name(mapped) do
    mapped
    |> Enum.reverse()
    |> Enum.join(".")
  end

  # The typespecs of OpentelemetryTelemetry.set_current_telemetry_span/2 are incorrect
  @dialyzer {:no_match, with_current_span: 2}
  defp with_current_span(telemetry_meta, function) do
    case OtelTranslator.set_current_telemetry_span(@tracer_id, telemetry_meta) do
      :undefined ->
        Logger.warning("Did not find active span information. Will ignore event.",
          telemetry_meta: telemetry_meta
        )

      span ->
        function.(span)
    end
  end

  defp to_otel_status({code, details}) when code in [:ok, :error] do
    cond do
      is_binary(details) ->
        :opentelemetry.status(code, details)

      is_exception(details) ->
        :opentelemetry.status(code, Exception.message(details))

      not is_nil(details) ->
        :opentelemetry.status(code, inspect(details))

      true ->
        :opentelemetry.status(code)
    end
  end

  defp to_otel_status(_), do: :opentelemetry.status(:unset)

  defp to_otel_attribute(string) when is_binary(string), do: string
  defp to_otel_attribute(number) when is_number(number), do: number
  defp to_otel_attribute(boolean) when is_boolean(boolean), do: boolean
  defp to_otel_attribute(atom) when is_atom(atom), do: atom

  defp to_otel_attribute(list) when is_list(list) do
    Enum.flat_map(list, &List.wrap(to_otel_attribute(&1)))
  end

  defp to_otel_attribute(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> to_otel_attribute()
    |> List.to_tuple()
  end

  defp to_otel_attribute(value), do: inspect(value)
end
