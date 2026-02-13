defmodule Witness.Source do
  @moduledoc """
  Any module that implements this behaviour is considered a source of the returned `context`.

  Usually there's no need to implement this behaviour manually as using the macros
  of `Witness.Tracker` automatically generates an implementation.
  """

  alias Witness

  @type info :: %{
          context: Witness.t(),
          events: nonempty_list(Witness.event_name())
        }

  @callback __observable__() :: info

  @doc "Checks if the given module implements the `c:__observable__/0` callback."
  @spec source?(module) :: boolean
  def source?(module) when is_atom(module) do
    function_exported?(module, :__observable__, 0)
  end

  @doc "Returns the info from the `c:__observable__/0` callback, or `nil` if it's not implemented."
  @spec info(module) :: nil | info
  def info(module) when is_atom(module) do
    if source?(module) do
      module.__observable__()
    end
  end

  @doc "Returns whatever value is set in the source `info/1`, or `nil`."
  @spec info(module, key :: :context | :events) :: nil | term
  def info(module, key) do
    case info(module) do
      nil -> nil
      %{^key => value} -> value
    end
  end

  @spec info!(module, key :: :context | :events) :: term
  def info!(module, key) do
    case info(module, key) do
      nil -> raise ArgumentError, "the given module is not a source of observability events: " <> inspect(module)
      value -> value
    end
  end
end
