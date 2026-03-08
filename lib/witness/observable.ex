defmodule Witness.Observable do
  @moduledoc """
  A content-addressed observation. Wraps bias.Observable.
  """

  @type t :: %__MODULE__{sha: String.t(), kind: String.t(), source: String.t()}
  defstruct [:sha, :kind, :source]

  @spec new(String.t(), String.t()) :: t()
  def new(kind, source) do
    content = "Observable(#{kind}, #{source})"
    sha = :bias.hash(content)
    %__MODULE__{sha: sha, kind: kind, source: source}
  end
end
