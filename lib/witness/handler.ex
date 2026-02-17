defmodule Witness.Handler do
  @moduledoc """
  A behaviour to implement observability handlers.

  Any module that implements this behaviour can be given as a `handler` to a
  `Witness` context.

  ## `c:child_spec/1`

  A Handler can also have OTP dependencies.

  If your handler requires further processes to be started it's recommended to
  implement the optional `c:child_spec/1` callback and return the child_spec of the
  dependency or a Supervisor that manages them.

  Adding a `Witness` context into a supervision tree also starts
  all it's handlers.
  """
  alias Witness

  require Logger

  @typedoc "A module which implements this behaviour."
  @type t :: module
  @type config :: any

  @doc "An optional child_spec. Use this to start any OTP dependencies your handler might need."
  @callback child_spec(Witness.t()) :: Supervisor.child_spec()

  @callback handle_event(
              Witness.event_name(),
              Witness.attributes(),
              Witness.meta(),
              config :: config
            ) :: any

  @optional_callbacks child_spec: 1

  @doc "Attaches the handler to all events emitted from all sources of the given context."
  @spec attach_to_context(handler_id :: any, handler :: t | {t, config}, context :: Witness.t()) ::
          :ok | {:error, {:unknown_app, atom}} | {:error, :already_exists}
  def attach_to_context(handler_id, {handler, config}, context) do
    Logger.info("Will attach handler to all events in context.",
      handler_id: inspect(handler_id),
      handler: handler,
      context: context
    )

    case Witness.sources_in(context) do
      {:ok, []} ->
        Logger.warning("Did not attach handler as the given context has no sources.",
          handler_id: handler_id,
          handler: handler,
          context: context
        )

        :ok

      {:ok, sources} ->
        events =
          sources
          |> Enum.flat_map(&Witness.Source.info!(&1, :events))
          |> Enum.concat(Witness.config(context, :extra_events))
          |> Enum.uniq()

        attach(handler_id, {handler, config}, events)

      {:error, {:unknown_app, app}} = error ->
        Logger.error(
          """
          Unknown OTP application: #{inspect(app)}

          The application is not loaded or does not exist. This usually means:
          1. The application name is misspelled in your Witness context
          2. The application hasn't been started yet
          3. The application doesn't exist in your project

          To fix:
          - Check the :app option in your Witness context configuration
          - Ensure the application is started: Application.ensure_all_started(#{inspect(app)})
          - Verify the application exists in mix.exs dependencies
          """,
          handler_id: handler_id,
          handler: handler,
          context: context,
          app: app
        )

        error

      {:error, reason} = error ->
        Logger.error("Did not attach handler as loading the context's sources failed.",
          handler_id: handler_id,
          handler: handler,
          context: context,
          error: reason
        )

        error
    end
  end

  def attach_to_context(handler_id, handler, context) do
    attach_to_context(handler_id, {handler, context}, context)
  end

  @doc false
  @spec attach(handler_id :: any, handler :: t | {t, config}, events :: [Witness.event_name()]) ::
          :ok | {:error, :already_exists}
  def attach(handler_id, {handler, config}, events) do
    if not (Code.ensure_loaded?(handler) and function_exported?(handler, :handle_event, 4)) do
      raise ArgumentError,
            "expected a module with a handle_event/4 function but the given module doesn't implement one (#{inspect(handler)})"
    end

    do_attach(handler_id, {handler, config}, events)
  end

  def attach(handler_id, handler, events), do: attach(handler_id, {handler, nil}, events)

  defp do_attach(_handler_id, _handler, []), do: :ok

  defp do_attach(handler_id, {handler, config}, events) do
    case :telemetry.attach_many(handler_id, events, &handler.handle_event/4, config) do
      :ok ->
        Logger.info("Did attach handler to events.",
          handler_id: inspect(handler_id),
          handler: handler,
          number_of_events: length(events)
        )

        :ok

      {:error, :already_exists} = error ->
        Logger.error("Did not attach handler to events; a handler with this ID is already attached.",
          handler_id: inspect(handler_id),
          handler: handler,
          events: events
        )

        error
    end
  end
end
