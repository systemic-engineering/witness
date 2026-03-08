defmodule Witness.Session.Ref do
  @moduledoc """
  Typed reference carrying a SHA and the layer it came from.
  Same pattern as cairn's Ref type (ObsRef/DecRef/ActRef).
  """

  @type t :: {:obs, String.t()} | {:dec, String.t()} | {:act, String.t()}

  @spec obs(String.t()) :: t()
  def obs(sha), do: {:obs, sha}

  @spec dec(String.t()) :: t()
  def dec(sha), do: {:dec, sha}

  @spec act(String.t()) :: t()
  def act(sha), do: {:act, sha}

  @spec sha(t()) :: String.t()
  def sha({_kind, sha}), do: sha

  @spec kind(t()) :: :obs | :dec | :act
  def kind({kind, _sha}), do: kind
end
