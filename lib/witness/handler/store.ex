defmodule Witness.Handler.Store do
  @moduledoc """
  A handler that routes telemetry events into a configured `Witness.Store`.

  Implements the `Witness.Handler` behaviour to bridge between the telemetry
  event pipeline and persistent storage backends.

  ## Configuration

  The handler config is a `{store_module, store_config}` tuple where:
  - `store_module` implements `Witness.Store`
  - `store_config` is a keyword list passed through to the store

  The store config must include a `:context` key identifying the Witness context.

  ## Example

      use Witness,
        handler: [
          {Witness.Handler.Store, {Witness.Store.Mnesia, context: MyApp.Observability}}
        ]
  """

  @behaviour Witness.Handler

  require Logger

  @impl Witness.Handler
  def handle_event(event_name, attributes, meta, {store_module, store_config}) do
    context = Keyword.fetch!(store_config, :context)

    case store_module.store_event(event_name, attributes, meta, context, store_config) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to store event #{inspect(event_name)}: #{inspect(reason)}",
          event: event_name,
          context: context,
          store: store_module
        )

        {:error, reason}
    end
  end

  @doc """
  Returns a child_spec for the configured store's OTP dependencies.

  Delegates to the store module's `child_spec/1` callback.
  """
  @impl Witness.Handler
  def child_spec({store_module, store_config}) do
    store_module.child_spec(store_config)
  end
end
