defmodule Witness.SpanRegistry do
  # How long tombstones are kept before being swept (milliseconds).
  @tombstone_ttl :timer.seconds(30)

  # How often the sweep runs (milliseconds).
  @sweep_interval :timer.seconds(30)

  @moduledoc """
  ETS-based registry for tracking active spans across process boundaries.

  Each entry is a `{pid, span_ref, status}` tuple where status is either
  `:active` (span is in progress) or `{:done, monotonic_ms}` (tombstone).

  Tombstones allow out-of-band processors to find the parent span ref even after
  the originating process has finished its span. A periodic sweep removes tombstones
  older than #{div(@tombstone_ttl, 1_000)} seconds.
  """

  use GenServer

  @type context :: Witness.t()
  @type span_ref :: reference()
  @type status :: :active | {:done, non_neg_integer()}

  @doc """
  Starts the span registry.
  """
  def start_link(context) do
    GenServer.start_link(__MODULE__, context, name: registry_name(context))
  end

  @doc """
  Child spec for supervision tree.
  """
  def child_spec(context) do
    %{
      id: {__MODULE__, context},
      start: {__MODULE__, :start_link, [context]},
      type: :worker
    }
  end

  @doc """
  Registers the current span for the calling process.

  If the registry is not started (e.g., in Mix tasks or when context is inactive),
  this is a no-op.
  """
  @spec register_span(context, span_ref) :: :ok
  def register_span(context, span_ref) do
    table = table_name(context)

    if table_exists?(table) do
      :ets.insert(table, {self(), span_ref, :active})
      GenServer.cast(registry_name(context), {:monitor, self()})
    end

    :ok
  end

  @doc """
  Marks the span for the calling process as done (tombstone).

  The entry is kept in ETS for `#{div(@tombstone_ttl, 1_000)}` seconds so that
  out-of-band processors can still look up the parent span ref after the originating
  process has finished its span.

  If the registry is not started (e.g., in Mix tasks or when context is inactive),
  this is a no-op.
  """
  @spec unregister_span(context, span_ref) :: :ok
  def unregister_span(context, span_ref) do
    table = table_name(context)

    if table_exists?(table) do
      :ets.insert(table, {self(), span_ref, {:done, System.monotonic_time(:millisecond)}})
      GenServer.cast(registry_name(context), {:demonitor, self()})
    end

    :ok
  end

  @doc """
  Looks up the span ref for the given PID.

  Returns `{:ok, span_ref}` for both active spans and tombstones.
  Returns `:error` if the registry is not started or no entry exists.
  """
  @spec lookup_span(context, pid) :: {:ok, span_ref} | :error
  def lookup_span(context, pid) do
    table = table_name(context)

    if table_exists?(table) do
      case :ets.lookup(table, pid) do
        [{^pid, span_ref, _status}] -> {:ok, span_ref}
        [] -> :error
      end
    else
      :error
    end
  end

  @doc """
  Looks up the parent span by checking the calling process's ancestors.

  Returns `{:ok, span_ref}` for both active spans and tombstones, enabling
  out-of-band processors to attach to a parent span even after it has completed.
  """
  @spec lookup_parent_span(context) :: {:ok, span_ref} | :error
  def lookup_parent_span(context) do
    case Process.get(:"$ancestors") do
      [parent_pid | _] when is_pid(parent_pid) ->
        lookup_span(context, parent_pid)

      _ ->
        :error
    end
  end

  @doc false
  @spec sweep(context, ttl_ms :: non_neg_integer()) :: :ok
  def sweep(context, ttl_ms \\ @tombstone_ttl) do
    GenServer.call(registry_name(context), {:sweep, ttl_ms})
  end

  ## GenServer Callbacks

  @impl true
  def init(context) do
    table =
      :ets.new(table_name(context), [
        :set,
        :public,
        :named_table,
        {:read_concurrency, true},
        {:write_concurrency, true}
      ])

    schedule_sweep()

    {:ok, %{context: context, table: table, monitors: %{}}}
  end

  @impl true
  def handle_cast({:monitor, pid}, state) do
    monitors =
      case state.monitors do
        %{^pid => {ref, count}} ->
          Map.put(state.monitors, pid, {ref, count + 1})

        _ ->
          ref = Process.monitor(pid)
          Map.put(state.monitors, pid, {ref, 1})
      end

    {:noreply, %{state | monitors: monitors}}
  end

  def handle_cast({:demonitor, pid}, state) do
    monitors =
      case state.monitors do
        %{^pid => {ref, 1}} ->
          Process.demonitor(ref, [:flush])
          Map.delete(state.monitors, pid)

        %{^pid => {ref, count}} ->
          Map.put(state.monitors, pid, {ref, count - 1})

        _ ->
          state.monitors
      end

    {:noreply, %{state | monitors: monitors}}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Tombstone the entry so out-of-band processors can still find the span ref.
    case :ets.lookup(state.table, pid) do
      [{^pid, span_ref, :active}] ->
        :ets.insert(state.table, {pid, span_ref, {:done, System.monotonic_time(:millisecond)}})

      _ ->
        :ok
    end

    {:noreply, %{state | monitors: Map.delete(state.monitors, pid)}}
  end

  def handle_info(:sweep, state) do
    do_sweep(state.table, @tombstone_ttl)
    schedule_sweep()
    {:noreply, state}
  end

  @impl true
  def handle_call({:sweep, ttl_ms}, _from, state) do
    do_sweep(state.table, ttl_ms)
    {:reply, :ok, state}
  end

  ## Private

  defp do_sweep(table, ttl_ms) do
    cutoff = System.monotonic_time(:millisecond) - ttl_ms
    match_spec = [{{:_, :_, {:done, :"$1"}}, [{:"=<", :"$1", cutoff}], [true]}]
    :ets.select_delete(table, match_spec)
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, @sweep_interval)

  defp registry_name(context), do: Module.concat(context, SpanRegistry)
  defp table_name(context), do: Module.concat(context, SpanRegistryTable)

  defp table_exists?(table) do
    :ets.whereis(table) != :undefined
  end
end
