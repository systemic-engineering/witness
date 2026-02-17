defmodule Witness.Tracker do
  @moduledoc """
  ## Usage
  ### Directly

      require #{inspect(__MODULE__)}, as: Tracker

      def my_cool_function(some_argument) do
        Tracker.with_span MyObservabilityContext, [:my, :span], %{some: "metadata"} do
          :do_some_cool_logic_here
        end
      end

      def another_function(another_argument) do
        Tracker.track_event MyObservabilityContext, [:my, :event], %{argument: another_argument}

        :logic_here
      end

  ### Using

      defmodule MyTracker do
        use #{inspect(__MODULE__)},
          context: MyObservabilityContext
      end

      #...

      require MyTracker

      def my_cool_function(some_argument) do
        MyTracker.with_span [:my, :span], %{some: "metadata"} do
          :do_some_cool_logic_here
        end
      end
  """
  alias Witness
  alias Witness.Span
  alias Witness.Utils

  require Witness

  @type context :: Witness.t()
  @type span_function(result) :: (-> result) | (Span.t() -> Span.t(result))

  @doc """
  Generate shortcut versions to all `#{inspect(__MODULE__)}` functions without having
  to explicitly specify the context module.

  ## Usage

      use #{inspect(__MODULE__)},
        context: MyObservabilityContext
  """
  defmacro __using__(context: context) do
    __MODULE__.Code.generate(:using, [context])
  end

  @empty_map Macro.escape(%{})

  sourcification = """
  It also remembers the emitted event and uses that to turn the caller into a `Witness.Source`.

  ## "Sourcification"

  Every time you call this macro the given event name will be retained. In a `@__before_compile__` hook the
  `#{inspect(__MODULE__)}` generates a `c:Witness.Source.__observabile__/0` function
  which returns the used context and all emitted events.

  This allows to subscribe to events emitted in a context without having to duplicate event names.
  """

  @doc """
  Emits a single `:telemetry` event under the context's `prefix`.

  ## Usage

      Tracker.track_event(MyObservabilityContext, [:my, :event, :name], %{attributes: "here", %{some: "optional metadata"})

  ## Emitted Event
  - `context.config()[:prefix] ++ event_name`

  #{sourcification}
  """
  defmacro track_event(context, event_name, attributes, meta \\ @empty_map) do
    __MODULE__.Code.generate(:track_event, [__CALLER__, context, event_name, attributes, meta])
  end

  @doc """
  Emits two `:telemetry` events under the context's `prefix`.

  ## Usage
  ### With a `do` block

      Tracker.with_span MyObservabilityContext, [:my, :span, :name], %{some: "optional metadata"} do
        # actual code here

        Tracker.add_span_metadata(more: "metadata")

        # actual code here
      end


  ### With a function

      alias Witness.Span

      Tracker.with_span(MyObservabilityContext, [:my, :span, :name], %{some: "optional metadata"}, fn span ->
        span
        |> Span.with_meta(more: "metadata")
        |> Span.with_result(
          # result of actual code
          :ok
        )
      end)

  ## Emitted Events
  - `context.config()[:prefix] ++ event_name ++ [:start]`
  - `context.config()[:prefix] ++ event_name ++ [:stop]`
  - `context.config()[:prefix] ++ event_name ++ [:exception]` (when an exception occurs)

      :telemetry.execute(
        context.config()[:prefix] ++ event_name,
        attributes,
        meta
      )

  #{sourcification}
  """
  defmacro with_span(context, event_name, meta \\ @empty_map, do_or_fn) do
    __MODULE__.Code.generate(:with_span, [__CALLER__, context, event_name, meta, do_or_fn])
  end

  @doc false
  @spec active_span(context) :: Span.t() | nil
  def active_span(context) do
    Process.get({__MODULE__, context, :active_span})
  end

  @doc false
  @spec set_active_span(context, Span.t() | nil) :: Span.t() | nil
  def set_active_span(context, nil), do: clear_active_span(context)

  def set_active_span(context, %Span{} = span) do
    Process.put({__MODULE__, context, :active_span}, span)
  end

  @doc false
  @spec clear_active_span(context) :: Span.t() | nil
  def clear_active_span(context) do
    Process.delete({__MODULE__, context, :active_span})
  end

  @doc "Adds metadata to the active span. Returns `false` when there is no active span."
  @spec add_span_meta(context, Witness.meta()) :: boolean
  def add_span_meta(context, meta) do
    update_active_span(context, &Span.with_meta(&1, meta))
  end

  @doc "Sets the status of the active span. Returns `false` when there is no active span."
  @spec set_span_status(context, Span.status_code(), Span.status_details()) :: boolean
  def set_span_status(context, status, details) when status in [:ok, :error, :unknown] do
    update_active_span(context, &Span.with_status(&1, status, details))
  end

  @doc """
  Sets the status of the active span. Returns `false` when there is no active span.

  Accepts:
  - `{:ok}` tuple
  - `{:error, reason}` tuple
  - `:ok`, `:error`, or `:unknown` atom (details default to nil)
  """
  @spec set_span_status(context, {:ok} | {:error, any()}) :: boolean
  @spec set_span_status(context, Span.status_code()) :: boolean
  def set_span_status(context, {:ok}) do
    set_span_status(context, :ok, nil)
  end

  def set_span_status(context, {:error, reason}) do
    set_span_status(context, :error, reason)
  end

  def set_span_status(context, status) when status in [:ok, :error, :unknown] do
    set_span_status(context, status, nil)
  end

  defp update_active_span(context, function) do
    case active_span(context) do
      %Span{} = span ->
        set_active_span(context, function.(span))
        true

      _ ->
        false
    end
  end

  makes_source_doc =
    "Use the macro version, as that transforms the calling module into a `Witness.Source`."

  @doc "The actual `track_event/4` logic. #{makes_source_doc}"
  @spec _track_event(context, Witness.event_name(), Witness.attributes(), Witness.meta()) :: :ok
  def _track_event(context, [_ | _] = event_name, attributes, meta) when Witness.is_context(context) do
    # Skip telemetry if context is inactive
    if Witness.config(context, :active) do
      :telemetry.execute(
        Witness.config(context, :prefix) ++ event_name,
        Utils.as_map(attributes),
        Utils.enrich_meta(meta, context: context, ref: make_ref())
      )
    else
      :ok
    end
  end

  @doc "The actual `with_span/4` logic. #{makes_source_doc}"
  @spec _with_span(context, Witness.event_name(), Witness.meta(), span_function(result)) :: result
        when result: any
  def _with_span(context, event_name, meta, span_function) when is_function(span_function, 0) do
    _with_span(context, event_name, meta, &Span.with_result(&1, span_function.()))
  end

  def _with_span(context, [_ | _] = event_name, meta, span_function)
      when Witness.is_context(context) and is_function(span_function, 1) do
    # Check if context is active - if not, just execute the function without telemetry
    if Witness.config(context, :active) do
      do_with_span(context, event_name, meta, span_function)
    else
      %Span{id: _ref} = span = Span.new(context, event_name, meta: meta)
      %Span{result: result} = span_function.(span)
      result
    end
  end

  defp do_with_span(context, event_name, meta, span_function) do
    %Span{id: ref} = span = Span.new(context, event_name, meta: meta)

    # Register span in ETS for cross-process tracking
    Witness.SpanRegistry.register_span(context, ref)

    try do
      :telemetry.span(
        Witness.config(context, :prefix) ++ event_name,
        Utils.enrich_meta(meta, context: context, ref: ref),
        fn ->
          %Span{result: result, meta: span_meta, status: status} = span_function.(span)

          {
            result,
            Utils.enrich_meta(span_meta, context: context, ref: ref, status: status)
          }
        end
      )
    after
      Witness.SpanRegistry.unregister_span(context, ref)
    end
  end
end
