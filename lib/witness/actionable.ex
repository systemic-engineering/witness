defmodule Witness.Actionable do
  @moduledoc """
  A content-addressed action. Wraps bias.Action.
  """

  @type t :: %__MODULE__{
          sha: String.t(),
          target: String.t(),
          config: [{String.t(), String.t()}]
        }

  defstruct [:sha, :target, config: []]

  @spec new(String.t(), [{String.t(), String.t()}]) :: t()
  def new(target, config \\ []) do
    content = "Action(#{target}, #{serialize_config(config)})"
    sha = :bias.hash(content)
    %__MODULE__{sha: sha, target: target, config: config}
  end

  defp serialize_config(pairs) do
    inner =
      pairs
      |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
      |> Enum.join(", ")

    "config[#{inner}]"
  end
end
