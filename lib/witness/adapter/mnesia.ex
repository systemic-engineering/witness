defmodule Witness.Adapter.Mnesia do
  @moduledoc """
  Mnesia-backed Ecto adapter for content-addressed commits.

  Uses `:bias.hash/1` for content addressing. Follows the same pattern as
  `Fragmentation.Store.ETS` but stores records in Mnesia tables.

  ## Configuration

      config :witness, Witness.InMemory,
        adapter: Witness.Adapter.Mnesia,
        storage_type: :ram_copies    # or :disc_copies
  """

  @behaviour Ecto.Adapter
  @behaviour Ecto.Adapter.Schema
  @behaviour Ecto.Adapter.Queryable

  # ===========================================================================
  # Ecto.Adapter — core callbacks
  # ===========================================================================

  @impl Ecto.Adapter
  defmacro __before_compile__(_env) do
    :ok
  end

  @impl Ecto.Adapter
  def ensure_all_started(_config, _type) do
    :mnesia.start()
    {:ok, [:mnesia]}
  end

  @impl Ecto.Adapter
  def init(config) do
    table = config[:otp_app] || :witness_commits
    storage_type = Keyword.get(config, :storage_type, :ram_copies)

    child_spec =
      Witness.Adapter.Mnesia.Server.child_spec(table: table, storage_type: storage_type)

    adapter_meta = %{table: table}
    {:ok, child_spec, adapter_meta}
  end

  @impl Ecto.Adapter
  def checkout(_adapter_meta, _config, fun) do
    fun.()
  end

  @impl Ecto.Adapter
  def checked_out?(_adapter_meta) do
    false
  end

  @impl Ecto.Adapter
  def loaders(_primitive, type) do
    [type]
  end

  @impl Ecto.Adapter
  def dumpers(_primitive, type) do
    [type]
  end

  # ===========================================================================
  # Ecto.Adapter.Schema — persistence callbacks
  # ===========================================================================

  @impl Ecto.Adapter.Schema
  def autogenerate(:id), do: nil
  def autogenerate(:binary_id), do: nil
  def autogenerate(:embed_id), do: Ecto.UUID.generate()

  @impl Ecto.Adapter.Schema
  def insert(adapter_meta, _schema_meta, fields, _on_conflict, returning, _opts) do
    table = adapter_meta.table

    data = Keyword.get(fields, :data, "")
    sha = Keyword.get(fields, :sha) || :bias.hash(data)
    message = Keyword.get(fields, :message)
    parent = Keyword.get(fields, :parent)

    record = {table, sha, data, message, parent}

    case :mnesia.transaction(fn -> :mnesia.write(record) end) do
      {:atomic, :ok} ->
        fields = Keyword.put(fields, :sha, sha)
        values = Enum.map(returning, fn key -> {key, Keyword.get(fields, key)} end)
        {:ok, values}

      {:aborted, reason} ->
        {:invalid, [mnesia: reason]}
    end
  end

  @impl Ecto.Adapter.Schema
  def insert_all(_, _, _, _, _, _, _, _) do
    raise "insert_all not supported — use insert/2"
  end

  @impl Ecto.Adapter.Schema
  def update(_, _, _, _, _, _) do
    raise "commits are immutable"
  end

  @impl Ecto.Adapter.Schema
  def delete(_, _, _, _, _) do
    raise "content-addressed stores don't delete"
  end

  # ===========================================================================
  # Ecto.Adapter.Queryable — query callbacks
  # ===========================================================================

  @impl Ecto.Adapter.Queryable
  def prepare(:all, query) do
    {:nocache, query}
  end

  @impl Ecto.Adapter.Queryable
  def execute(adapter_meta, _query_meta, {:nocache, query}, params, _opts) do
    table = adapter_meta.table
    {_source, schema} = query.from.source

    case params do
      [sha] when is_binary(sha) ->
        case :mnesia.transaction(fn -> :mnesia.read(table, sha) end) do
          {:atomic, [{^table, sha, data, message, parent}]} ->
            fields = [sha: sha, data: data, message: message, parent: parent]
            row = Enum.map(schema.__schema__(:fields), fn key -> Keyword.get(fields, key) end)
            {1, [row]}

          _ ->
            {0, []}
        end

      _ ->
        {0, []}
    end
  end

  @impl Ecto.Adapter.Queryable
  def stream(_, _, _, _, _) do
    raise "streaming not supported"
  end
end
