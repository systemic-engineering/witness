defmodule Witness.Tracker.Code do
  @moduledoc """
  Code generation for the `Witness.Tracker` module.

  The `generate(:using, ...)` call effectively mirrors the API of `Witness.Tracker`
  while the other two `generate/2` clauses contain the actual tracking code.
  """
  alias Witness

  @attributes %{
    context: :__observable_context__,
    events: :__observable_events__
  }

  @doc false
  def generate(:using, [context]), do: build_using_quote(context)

  def generate(:track_event, [caller, context, event_name, attributes, meta]) do
    enforce_static_event_name!(caller, :track_event, event_name)

    remember_event(caller, context, event_name)

    meta = include_caller(caller, meta)

    quote do
      Witness.Tracker._track_event(
        unquote(context),
        unquote(event_name),
        unquote(attributes),
        unquote(meta)
      )
    end
  end

  def generate(:with_span, [caller, context, event_name, meta, do_or_fn]) do
    enforce_static_event_name!(caller, :with_span, event_name)

    # These are all the events that :telemetry.span/3 emits
    remember_event(caller, context, event_name, [:start])
    remember_event(caller, context, event_name, [:stop])
    remember_event(caller, context, event_name, [:exception])

    meta = include_caller(caller, meta)
    {span_var, code} = extract_span_var_and_code(do_or_fn)

    build_with_span_quote(context, event_name, meta, span_var, code)
  end

  defp build_with_span_quote(context, event_name, meta, span_var, code) do
    quote generated: true, location: :keep do
      Witness.Tracker._with_span(
        unquote(context),
        unquote(event_name),
        unquote(meta),
        fn span ->
          old_span = Witness.Tracker.set_active_span(unquote(context), span)

          try do
            # This escapes Macro hygiene by assigning `span` to a variable of the callers choice
            unquote(span_var) = span
            unquote(code)
          else
            %Witness.Span{} = span ->
              span

            result ->
              unquote(context)
              |> Witness.Tracker.active_span()
              |> Witness.Span.with_result(result)
          after
            Witness.Tracker.set_active_span(unquote(context), old_span)
          end
        end
      )
    end
  end

  defp enforce_static_event_name!(%{file: file, line: line}, macro_name, event_name) do
    if valid_event_name?(event_name) do
      :ok
    else
      raise CompileError,
        file: file,
        line: line,
        description: """
        Event names need to be a static list of atoms.

            > #{macro_name} #{Macro.to_string(event_name)} ...
            #{invalid_event_name_indicator("> #{macro_name} ", event_name)} (not a static list of atoms)

            All event names need to be known at compile time, to be able to reliably attach event handlers to them.
            Handlers get attached to an event's exact name; as such dynamic event names are discouraged and not supported.
        """
    end
  end

  defp valid_event_name?([bare_atom | rest]) when is_atom(bare_atom), do: valid_event_name?(rest)
  defp valid_event_name?([]), do: true
  defp valid_event_name?(_), do: false

  defp invalid_event_name_indicator(prefixed_by, event_name) when is_binary(prefixed_by) do
    extra_indentation =
      if is_list(event_name) do
        # +1 for the leading `[`
        1
      else
        0
      end

    invalid_event_name_indicator(String.length(prefixed_by) + extra_indentation, event_name)
  end

  defp invalid_event_name_indicator(indentation, [atom | event_name]) when is_atom(atom) do
    # +2 for `, ` after the item
    invalid_event_name_indicator(indentation + length_as_code(atom) + 2, event_name)
  end

  defp invalid_event_name_indicator(indentation, invalid) do
    invalid =
      case invalid do
        [not_an_static_atom | _] -> not_an_static_atom
        not_a_list -> not_a_list
      end

    String.duplicate(" ", indentation) <> String.duplicate("^", length_as_code(invalid))
  end

  defp length_as_code(ast) do
    ast
    |> Macro.to_string()
    |> String.length()
  end

  defp remember_event(caller, context, event_name, postfix \\ [])

  defp remember_event(caller, {:__aliases__, _, _} = context, event_name, postfix) do
    # Resolve the aliased context module to it's full name
    {resolved_context, _bindings, _env} = Code.eval_quoted_with_env(context, [], caller)

    remember_event(caller, resolved_context, event_name, postfix)
  end

  defp remember_event(%{module: module}, context, event_name, postfix) do
    if not Module.has_attribute?(module, @attributes.context) do
      Module.put_attribute(module, :before_compile, __MODULE__)
      Module.put_attribute(module, @attributes.context, context)
      Module.register_attribute(module, @attributes.events, accumulate: true)
    end

    Module.put_attribute(module, @attributes.events, Witness.config(context, :prefix) ++ event_name ++ postfix)
  end

  # No meta passed, generate the static meta at compile time
  defp include_caller(%{module: module, function: function}, {:%{}, _, []}) do
    %{}
    |> Witness.Utils.enrich_meta(%{caller: {module, function}})
    |> Macro.escape()
  end

  defp include_caller(%{module: module, function: function}, meta) do
    quote do
      Witness.Utils.enrich_meta(
        unquote(meta),
        %{caller: unquote({module, function})}
      )
    end
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp build_using_quote(context) do
    quote bind_quoted: [context: context], location: :keep do
      alias Witness

      context_name = inspect(context)

      @doc "Delegates to `Witness.Tracker.track_event/4` with the `#{context_name}` context."
      @empty_map Macro.escape(%{})
      defmacro track_event(event_name, attributes, meta \\ @empty_map) do
        Witness.Tracker.Code.generate(:track_event, [
          __CALLER__,
          unquote(context),
          event_name,
          attributes,
          meta
        ])
      end

      @doc "Delegates to `Witness.Tracker.with_span/4` with the `#{context_name}` context."
      defmacro with_span(event_name, meta \\ @empty_map, do_or_fn) do
        Witness.Tracker.Code.generate(:with_span, [
          __CALLER__,
          unquote(context),
          event_name,
          meta,
          do_or_fn
        ])
      end

      @doc "Delegates to `Witness.Tracker.active_span/1` with the `#{context_name}` context."
      @spec active_span() :: Witness.Span.t() | nil
      def active_span do
        Witness.Tracker.active_span(unquote(context))
      end

      @doc "Delegates to `Witness.Tracker.set_active_span/2` with the `#{context_name}` context."
      @spec set_active_span(Witness.Span.t() | nil) :: Witness.Span.t() | nil
      def set_active_span(span_or_nil) do
        Witness.Tracker.set_active_span(unquote(context), span_or_nil)
      end

      @doc "Delegates to `Witness.Tracker.add_span_metadata/2` with the `#{context_name}` context."
      @spec add_span_meta(Witness.meta()) :: boolean
      def add_span_meta(meta) do
        Witness.Tracker.add_span_meta(unquote(context), meta)
      end

      @doc """
      Delegates to `Witness.Tracker.set_span_status/2` or `/3` with the `#{context_name}` context.

      Accepts:
      - `{:ok}` or `{:error, reason}` tuples
      - `:ok`, `:error`, or `:unknown` atoms with optional details
      """
      @spec set_span_status({:ok} | {:error, any()}) :: boolean
      @spec set_span_status(Witness.Span.status_code(), Witness.Span.status_details()) :: boolean
      def set_span_status(status_or_tuple, details \\ nil)

      def set_span_status({:ok}, _details) do
        Witness.Tracker.set_span_status(unquote(context), {:ok})
      end

      def set_span_status({:error, reason}, _details) do
        Witness.Tracker.set_span_status(unquote(context), {:error, reason})
      end

      def set_span_status(status, details) when status in [:ok, :error, :unknown] do
        Witness.Tracker.set_span_status(unquote(context), status, details)
      end
    end
  end

  @underscore quote(do: _)
  # do <code> end
  defp extract_span_var_and_code(do: code), do: {@underscore, code}
  # fn -> <code> end
  defp extract_span_var_and_code({:fn, _, [{:->, _, [[], code]}]}), do: {@underscore, code}
  # fn <span_arg> -> <code> end
  defp extract_span_var_and_code({:fn, _, [{:->, _, [[span_arg], code]}]}), do: {span_arg, code}

  @doc false
  defmacro __before_compile__(%{module: module}) do
    context = Module.get_attribute(module, @attributes.context)

    events =
      module
      |> Module.get_attribute(@attributes.events)
      |> Enum.reverse()
      |> Enum.uniq()

    quote do
      @doc false
      @behaviour Witness.Source
      @impl Witness.Source
      def __observable__ do
        %{
          context: unquote(context),
          events: unquote(events)
        }
      end
    end
  end
end
