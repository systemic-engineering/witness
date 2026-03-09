defmodule Witness.Session do
  @moduledoc """
  ODA state machine for a witnessed session.

  Delegates to `Witness.Session.State` for the pure functional ODA
  implementation. This module preserves the public API and struct
  for backward compatibility during the Session GenServer migration.
  """

  alias Witness.Session.State

  @type t :: State.t()
  @type config :: State.config()
  @type entry :: State.entry()

  defstruct config: %{author: "", name: ""},
            store: [],
            last_root: nil,
            head: ""

  defdelegate new(config), to: State
  defdelegate head(session), to: State
  defdelegate config(session), to: State
  defdelegate last_root(session), to: State
  defdelegate act(session, annotation, data), to: State
  defdelegate decide(session, annotation, obs_ref, rule, act_shas), to: State
  defdelegate observe(session, annotation, ref, data, decision_shas), to: State
  defdelegate commit(session, annotation, observation_shas), to: State
end
