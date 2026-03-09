defmodule Witness.Server do
  @moduledoc """
  Starts the local Witness observability field.

  Supervises the default Ecto repo (Mnesia-backed) used by the MCP server's
  Actor state machine. Add to your supervision tree to get AI-native
  observability immediately, with no external infrastructure.

  ## Usage

  In your application supervisor:

      children = [
        Witness.Server,
        # ... rest of your app
      ]

  Or standalone via `mix witness`.

  ## MCP config

  Add to your project's `.mcp.json`:

      {
        "mcpServers": {
          "witness": {
            "command": "mix",
            "args": ["witness"]
          }
        }
      }
  """

  use Supervisor

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl Supervisor
  def init(_opts) do
    children = [
      Witness.DefaultRepo
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
