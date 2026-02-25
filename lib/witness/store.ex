defmodule Witness.Store do
  @moduledoc """
  A behaviour for persistent event storage backends.

  Any module that implements this behaviour can be used as a `:store` in a
  `Witness` context configuration. Events flowing through the telemetry pipeline
  are persisted via `c:store_event/5` and can be queried via `c:list_events/3`.

  ## Example

      use Witness,
        app: :my_app,
        prefix: [:my_context],
        store: {Witness.Store.Mnesia, []}

  ## Implementing a Store

      defmodule MyApp.Store.Custom do
        @behaviour Witness.Store

        @impl true
        def store_event(event_name, attributes, meta, context, config) do
          # Persist the event
          :ok
        end

        @impl true
        def list_events(context, query_opts, config) do
          # Query persisted events
          {:ok, []}
        end

        @impl true
        def child_spec(config) do
          # Return a child_spec for any processes this store needs
          %{id: __MODULE__, start: {__MODULE__, :start_link, [config]}}
        end
      end
  """

  @type event_name :: [atom()]
  @type attributes :: map()
  @type meta :: map()
  @type context :: module()
  @type config :: keyword()
  @type query_opts :: keyword()

  @doc "Persists a telemetry event."
  @callback store_event(event_name, attributes, meta, context, config) :: :ok | {:error, term()}

  @doc "Lists persisted events for the given context, filtered by query options."
  @callback list_events(context, query_opts, config) :: {:ok, [map()]} | {:error, term()}

  @doc "Returns a child_spec for any OTP processes the store requires."
  @callback child_spec(config) :: Supervisor.child_spec()
end
