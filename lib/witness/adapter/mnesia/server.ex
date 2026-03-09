defmodule Witness.Adapter.Mnesia.Server do
  @moduledoc """
  GenServer that owns the Mnesia table for the Mnesia adapter.
  """

  use GenServer

  require Logger

  def start_link(opts) do
    table = Keyword.get(opts, :table, :witness_commits)
    storage_type = Keyword.get(opts, :storage_type, :ram_copies)
    GenServer.start_link(__MODULE__, {table, storage_type}, name: __MODULE__)
  end

  @impl GenServer
  def init({table, storage_type}) do
    create_table(table, storage_type)
    {:ok, table}
  end

  defp create_table(table, storage_type) do
    opts = [
      {storage_type, [node()]},
      attributes: [:sha, :data, :message, :parent],
      type: :set
    ]

    case :mnesia.create_table(table, opts) do
      {:atomic, :ok} ->
        Logger.info("Created Mnesia table #{inspect(table)} with #{storage_type}")

      {:aborted, {:already_exists, ^table}} ->
        :ok

      {:aborted, reason} ->
        Logger.error("Failed to create Mnesia table #{inspect(table)}: #{inspect(reason)}")
    end
  end
end
