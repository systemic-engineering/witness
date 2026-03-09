defmodule Witness.Session.State do
  @moduledoc """
  Pure functional ODA state machine for a witnessed session.

  Port of cairn's session.gleam. Struct + functions, NOT a GenServer.
  State threading through function returns.

  Operates on `%Witness.Session{}` structs. The struct definition lives
  on `Witness.Session`; this module provides the pure ODA functions.

  ADO structure (built bottom-up):
    root           <- commit (seals session)
      observation  <- observe (wraps decisions)
        decision   <- decide (wraps acts, linked to observation)
          action   <- act (terminal)

  Each operation emits telemetry automatically via `:telemetry.execute/3`.
  Existing handlers (Logger, Store, etc.) pick up ODA events for free.
  """

  alias Witness.Session
  alias Witness.Session.Ref

  @spec new(Session.config()) :: Session.t()
  def new(config) do
    %Session{config: config}
  end

  @spec head(Session.t()) :: String.t()
  def head(%Session{head: head}), do: head

  @spec config(Session.t()) :: Session.config()
  def config(%Session{config: config}), do: config

  @spec last_root(Session.t()) :: {Session.entry(), String.t()} | nil
  def last_root(%Session{last_root: last_root}), do: last_root

  # ---------------------------------------------------------------------------
  # ODA — build bottom-up: Act -> Decide -> Observe -> Commit
  # ---------------------------------------------------------------------------

  @spec act(Session.t(), String.t(), String.t()) :: {Session.t(), Ref.t()}
  def act(%Session{} = state, annotation, data) do
    content = annotation <> "\n" <> data
    sha = :bias.hash(content)
    entry = %{kind: :act, data: data, children: [], annotation: annotation}

    updated = %{
      state
      | store: state.store ++ [{sha, entry}],
        head: sha
    }

    :telemetry.execute(
      [:witness, :session, :act],
      %{system_time: System.system_time()},
      %{
        annotation: annotation,
        data: data,
        sha: sha,
        author: state.config.author
      }
    )

    {updated, Ref.act(sha)}
  end

  @spec decide(Session.t(), String.t(), Ref.t(), String.t(), [String.t()]) :: {Session.t(), Ref.t()}
  def decide(%Session{} = state, annotation, obs_ref, rule, act_shas) do
    obs_sha = Ref.sha(obs_ref)
    children_sha = Enum.join(act_shas)
    content = obs_sha <> rule <> children_sha
    sha = :bias.hash(content)
    entry = %{kind: :dec, data: rule, children: act_shas, annotation: annotation}

    updated = %{
      state
      | store: state.store ++ [{sha, entry}],
        head: sha
    }

    :telemetry.execute(
      [:witness, :session, :decide],
      %{system_time: System.system_time()},
      %{
        annotation: annotation,
        rule: rule,
        obs_ref: obs_sha,
        sha: sha,
        author: state.config.author
      }
    )

    {updated, Ref.dec(sha)}
  end

  @spec observe(Session.t(), String.t(), String.t(), String.t(), [String.t()]) :: {Session.t(), Ref.t()}
  def observe(%Session{} = state, annotation, ref, data, decision_shas) do
    children_sha = Enum.join(decision_shas)
    content = ref <> data <> children_sha
    sha = :bias.hash(content)
    entry = %{kind: :obs, data: data, children: decision_shas, annotation: annotation}

    updated = %{
      state
      | store: state.store ++ [{sha, entry}],
        head: sha
    }

    :telemetry.execute(
      [:witness, :session, :observe],
      %{system_time: System.system_time()},
      %{
        annotation: annotation,
        ref: ref,
        data: data,
        sha: sha,
        author: state.config.author
      }
    )

    {updated, Ref.obs(sha)}
  end

  @spec commit(Session.t(), String.t(), [String.t()]) :: {Session.t(), Session.entry(), String.t()}
  def commit(%Session{} = state, annotation, observation_shas) do
    name = state.config.name
    children_sha = Enum.join(observation_shas)
    content = name <> children_sha
    sha = :bias.hash(content)
    entry = %{kind: :root, data: name, children: observation_shas, annotation: annotation}

    updated = %{
      state
      | last_root: {entry, sha},
        head: sha
    }

    :telemetry.execute(
      [:witness, :session, :commit],
      %{system_time: System.system_time()},
      %{
        annotation: annotation,
        name: name,
        sha: sha,
        author: state.config.author
      }
    )

    {updated, entry, sha}
  end
end
