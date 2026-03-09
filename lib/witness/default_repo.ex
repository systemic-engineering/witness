defmodule Witness.DefaultRepo do
  @moduledoc """
  Default in-memory Ecto.Repo for the Witness MCP server.

  Uses `Witness.Adapter.Mnesia` with `ram_copies`. Ships as the default
  for `mix witness` — no configuration needed.
  """

  use Witness.Repo
end
