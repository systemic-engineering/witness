defmodule Witness.InMemory.Sync do
  @moduledoc """
  Subscribes to `Witness.InMemory`'s Mnesia table and syncs new writes
  to a configured downstream repo.

  InMemory is the source of truth. This process is the push path outward.
  Only new inserts are forwarded — updates are not possible in a
  content-addressed store, so events with non-empty old_records are ignored.

  ## Usage

  Started by `Witness.Server` when a `sync_repo:` is configured:

      Witness.Server.start_link(sync_repo: MyApp.Repo)

  Or directly for testing:

      Witness.InMemory.Sync.start_link(repo: MyRepo, table: :witness)
  """

  use GenServer

  require Logger

  @default_table :witness

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def start_link(opts) do
    repo = Keyword.fetch!(opts, :repo)
    table = Keyword.get(opts, :table, @default_table)
    GenServer.start_link(__MODULE__, {repo, table})
  end

  @impl GenServer
  def init({repo, table}) do
    :mnesia.subscribe({:table, table, :detailed})
    Logger.info("Witness.InMemory.Sync started — syncing #{inspect(table)} → #{inspect(repo)}")
    {:ok, %{repo: repo, table: table}}
  end

  # New insert: old_records is empty.
  @impl GenServer
  def handle_info({:mnesia_table_event, {:write, event_table, record, [], _activity}}, state) do
    if event_table == state.table do
      {_, sha, data, message, parent} = record
      event = %Witness.Event{sha: sha, data: data, message: message, parent: parent}
      state.repo.insert(event)
    end

    {:noreply, state}
  end

  # Update or other event — ignore (content-addressed store is immutable).
  def handle_info({:mnesia_table_event, _}, state), do: {:noreply, state}
  def handle_info(_, state), do: {:noreply, state}
end
