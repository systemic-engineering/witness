defmodule Witness.Guards do
  @moduledoc false

  @doc """
  A guard that checks if the given value is a context module.

  To be specific it only checks if the given value is an atom and not nil. As
  further checks are not possible in guards. If you'd like to be certain use
  `Witness.context?/1`.
  """
  defguard is_context(context) when is_atom(context) and not is_nil(context)
end
