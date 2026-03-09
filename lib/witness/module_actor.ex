defmodule Witness.ModuleActor do
  @moduledoc """
  A GenServer representing a witnessed module in the runtime.

  Each `Witness.ModuleActor` holds the live `%Witness{}` state for a module
  and registers itself in `Witness.Registry` for lookup by module atom.
  """
  use GenServer

  @doc "Start and register a ModuleActor for the given witnessed module."
  def start_link(module) do
    GenServer.start_link(__MODULE__, module, name: {:via, Registry, {Witness.Registry, module}})
  end

  @impl true
  def init(module) do
    witness = Witness.start(module)
    {:ok, witness}
  end

  @impl true
  def handle_call(:__witness__, _from, witness) do
    {:reply, witness, witness}
  end
end
