defmodule Witness.Store.Ecto.Event do
  @moduledoc """
  Event schema for the Ecto store adapter.

  Mirrors `Fragmentation.Commit` shape exactly — the ETS adapter requires
  `:sha`, `:data`, `:message`, `:parent` fields.
  """

  use Ecto.Schema

  @primary_key false
  schema "witness_events" do
    field(:sha, :string, primary_key: true, read_after_writes: true)
    field(:data, :string)
    field(:message, :string)
    field(:parent, :string)
  end
end
