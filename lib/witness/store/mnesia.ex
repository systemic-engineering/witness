defmodule Witness.Store.Mnesia do
  @moduledoc """
  A Mnesia-backed persistent store for Witness events.

  Manages context-scoped Mnesia tables. Each Witness context gets its own table,
  named `Module.concat(context, WitnessEvents)`, providing isolation between
  contexts.

  ## Table Design

  - **Key:** `{timestamp_us, ref}` — an `ordered_set` gives chronological ordering
    with uniqueness guaranteed by the ref.
  - **Storage:** `ram_copies` by default, configurable to `disc_copies` via the
    `:storage_type` option.
  - **Writes:** Direct `:mnesia.write/3` on the hot path (no GenServer call).

  ## Configuration

      # ram_copies (default)
      store: {Witness.Store.Mnesia, []}

      # disc_copies for persistence across restarts
      store: {Witness.Store.Mnesia, storage_type: :disc_copies}

  ## Query Options

  `list_events/3` supports the following filters:

  - `:after` — only events after this timestamp (microseconds since epoch)
  - `:before` — only events before this timestamp (microseconds since epoch)
  - `:limit` — maximum number of events to return
  - `:event_name` — only events matching this event name (list of atoms)
  """

  @behaviour Witness.Store

  use GenServer

  require Logger

  # Mnesia record: {table, {timestamp_us, ref}, event_name, attributes, meta}
  @record_fields [:key, :event_name, :attributes, :meta]

  ## Public API

  @doc "Starts the Mnesia store GenServer for the given config."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(config) do
    context = Keyword.fetch!(config, :context)
    GenServer.start_link(__MODULE__, config, name: server_name(context))
  end

  @impl Witness.Store
  def child_spec(config) do
    context = Keyword.fetch!(config, :context)

    %{
      id: {__MODULE__, context},
      start: {__MODULE__, :start_link, [config]},
      type: :worker
    }
  end

  @impl Witness.Store
  def store_event(event_name, attributes, meta, context, _config) do
    table = table_name(context)
    key = {System.system_time(:microsecond), make_ref()}
    record = {table, key, event_name, attributes, meta}

    case :mnesia.transaction(fn -> :mnesia.write(record) end) do
      {:atomic, :ok} -> :ok
      {:aborted, reason} -> {:error, reason}
    end
  end

  @impl Witness.Store
  def list_events(context, query_opts, _config) do
    table = table_name(context)
    after_ts = Keyword.get(query_opts, :after)
    before_ts = Keyword.get(query_opts, :before)
    limit = Keyword.get(query_opts, :limit)
    event_name_filter = Keyword.get(query_opts, :event_name)

    result =
      :mnesia.transaction(fn ->
        # Build match spec for :mnesia.select/2
        # Record pattern: {table, {ts, ref}, event_name, attributes, meta}
        match_head = {table, {:"$1", :"$2"}, :"$3", :"$4", :"$5"}

        # Build guards
        guards = build_guards(after_ts, before_ts, event_name_filter)

        # Result: reconstruct into a map
        result = [%{key: {{:"$1", :"$2"}}, event_name: :"$3", attributes: :"$4", meta: :"$5"}]

        match_spec = [{match_head, guards, result}]
        records = :mnesia.select(table, match_spec)

        # Sort by key (timestamp, ref) — ordered_set gives us order on traversal
        # but :mnesia.select may not preserve it, so sort explicitly
        sorted = Enum.sort_by(records, & &1.key)

        # Apply limit
        if limit do
          Enum.take(sorted, limit)
        else
          sorted
        end
      end)

    case result do
      {:atomic, events} -> {:ok, events}
      {:aborted, reason} -> {:error, reason}
    end
  end

  ## GenServer Callbacks

  @impl GenServer
  def init(config) do
    context = Keyword.fetch!(config, :context)
    storage_type = Keyword.get(config, :storage_type, :ram_copies)
    table = table_name(context)

    create_table(table, storage_type)

    {:ok, %{context: context, table: table}}
  end

  ## Private

  defp create_table(table, storage_type) do
    opts = [
      attributes: @record_fields,
      type: :ordered_set
    ]

    opts = [{storage_type, [node()]} | opts]

    case :mnesia.create_table(table, opts) do
      {:atomic, :ok} ->
        Logger.info("Created Mnesia table #{inspect(table)} with #{storage_type}")
        :ok

      {:aborted, {:already_exists, ^table}} ->
        Logger.debug("Mnesia table #{inspect(table)} already exists")
        :ok

      {:aborted, reason} ->
        Logger.error("Failed to create Mnesia table #{inspect(table)}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_guards(after_ts, before_ts, event_name_filter) do
    guards = []

    guards =
      if after_ts do
        [{:>, :"$1", after_ts} | guards]
      else
        guards
      end

    guards =
      if before_ts do
        [{:<, :"$1", before_ts} | guards]
      else
        guards
      end

    guards =
      if event_name_filter do
        [{:==, :"$3", event_name_filter} | guards]
      else
        guards
      end

    guards
  end

  defp table_name(context), do: Module.concat(context, WitnessEvents)
  defp server_name(context), do: Module.concat(context, WitnessStore)
end
