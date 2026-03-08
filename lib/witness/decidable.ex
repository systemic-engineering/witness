defmodule Witness.Decidable do
  @moduledoc """
  A content-addressed decision variant. Wraps bias.Decision.
  """

  @type t :: %__MODULE__{
          sha: String.t(),
          variant: String.t(),
          payload: [{String.t(), String.t()}]
        }

  defstruct [:sha, :variant, payload: []]

  @spec new(String.t(), [{String.t(), String.t()}]) :: t()
  def new(variant, payload \\ []) do
    content = "Decision(#{variant}, #{serialize_payload(payload)})"
    sha = :bias.hash(content)
    %__MODULE__{sha: sha, variant: variant, payload: payload}
  end

  defp serialize_payload(pairs) do
    inner =
      pairs
      |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
      |> Enum.join(", ")

    "payload[#{inner}]"
  end
end
