defmodule Witness.Registry do
  @moduledoc """
  Module-to-PID registry for witnessed modules.

  Thin wrapper around Elixir's `Registry` with `:unique` keys,
  mapping module atoms to their `Witness.Actor` PIDs.
  """

  def child_spec(_) do
    Registry.child_spec(keys: :unique, name: __MODULE__)
  end

  @spec register(module) :: :ok | {:error, term}
  def register(module) do
    case Registry.register(__MODULE__, module, nil) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @spec unregister(module) :: :ok
  def unregister(module) do
    Registry.unregister(__MODULE__, module)
  end

  @spec lookup(module) :: {:ok, pid} | :error
  def lookup(module) do
    case Registry.lookup(__MODULE__, module) do
      [{pid, _}] -> {:ok, pid}
      [] -> :error
    end
  end
end
