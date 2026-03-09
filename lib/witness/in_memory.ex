defmodule Witness.InMemory do
  @moduledoc """
  In-memory Ecto.Repo for the Witness MCP server. Always running.

  Uses `Witness.Adapter.Mnesia` with `ram_copies`. Source of truth for all
  Actor writes. Syncs downstream to a configured repo via `Witness.InMemory.Sync`.
  """

  use Witness.Repo
end
