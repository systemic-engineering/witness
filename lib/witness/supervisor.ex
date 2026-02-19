defmodule Witness.Supervisor do
  @moduledoc """
  Attaches and starts all handlers of the given `Witness` context.

  Fundamentally what the Supervisor does is this:
  1. load all `handler`s of the given context (`Witness.config(context, :handler)`)
  2. attach every handler to every event of the context (`Witness.Handler.attach_to_context/3`)
  3. start all handlers that implement a `child_spec/1`
  """
  @behaviour Supervisor

  require Witness.Guards
  import Witness.Guards, only: [is_context: 1]
  require Logger

  @typedoc "A child_spec for an instance of this Supervisor."
  @type child_spec :: Supervisor.child_spec()

  @doc false
  @spec child_spec(Witness.t()) :: child_spec()
  def child_spec(context) when is_context(context) do
    # coveralls-ignore-next-line
    %{
      id: {__MODULE__, context},
      start: {__MODULE__, :start_link, [context]},
      type: :supervisor
    }
  end

  @doc false
  def start_link(context) when is_context(context) do
    # coveralls-ignore-next-line
    Supervisor.start_link(__MODULE__, context, name: context)
  end

  @impl true
  def init(context) do
    if Witness.config(context, :active) do
      Logger.info("Will load and start all handlers for context.", context: context)

      handlers =
        context
        |> load_handler()
        |> attach_to_context!(context)
        |> only_with_child_spec()

      # Add SpanRegistry as first child
      children = [Witness.SpanRegistry.child_spec(context) | handlers]

      Supervisor.init(children, strategy: :one_for_one)
    else
      Logger.notice("Will not attach or start handlers for context, as it's inactive.", context: context)

      Supervisor.init([], strategy: :one_for_one)
    end
  end

  defp load_handler(context) do
    context
    |> Witness.config(:handler)
    |> Enum.map(fn
      {module, config} -> {module, config}
      module -> {module, context}
    end)
  end

  defp attach_to_context!(handler, context) do
    for h <- handler do
      handler_id = {context, h}

      :ok = Witness.Handler.attach_to_context(handler_id, h, context)

      h
    end
  end

  defp only_with_child_spec(handler) do
    Enum.filter(handler, fn {module, _config} ->
      function_exported?(module, :child_spec, 1)
    end)
  end
end
