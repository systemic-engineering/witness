defmodule Witness.Session do
  @moduledoc """
  ODA state machine for a witnessed session.

  Port of cairn's session.gleam. Pure functional module — struct + functions,
  NOT a GenServer. State threading through function returns.

  ADO structure (built bottom-up):
    root           ← commit (seals session)
      observation  ← observe (wraps decisions)
        decision   ← decide (wraps acts, linked to observation)
          action   ← act (terminal)

  Each operation emits telemetry automatically via `:telemetry.execute/3`.
  Existing handlers (Logger, Store, etc.) pick up ODA events for free.
  """

  alias Witness.Session.Ref

  @type t :: %__MODULE__{
          config: config(),
          store: [{String.t(), entry()}],
          last_root: {entry(), String.t()} | nil,
          head: String.t()
        }

  @type config :: %{author: String.t(), name: String.t()}

  @type entry :: %{
          kind: :obs | :dec | :act | :root,
          data: String.t(),
          children: [String.t()],
          annotation: String.t()
        }

  defstruct config: %{author: "", name: ""},
            store: [],
            last_root: nil,
            head: ""

  @spec new(config()) :: t()
  def new(config) do
    %__MODULE__{config: config}
  end

  @spec head(t()) :: String.t()
  def head(%__MODULE__{head: head}), do: head

  @spec config(t()) :: config()
  def config(%__MODULE__{config: config}), do: config

  @spec last_root(t()) :: {entry(), String.t()} | nil
  def last_root(%__MODULE__{last_root: last_root}), do: last_root

  # ---------------------------------------------------------------------------
  # ODA — build bottom-up: Act → Decide → Observe → Commit
  # ---------------------------------------------------------------------------

  @spec act(t(), String.t(), String.t()) :: {t(), Ref.t()}
  def act(%__MODULE__{} = session, annotation, data) do
    content = annotation <> "\n" <> data
    sha = :bias.hash(content)
    entry = %{kind: :act, data: data, children: [], annotation: annotation}

    updated = %{
      session
      | store: session.store ++ [{sha, entry}],
        head: sha
    }

    :telemetry.execute(
      [:witness, :session, :act],
      %{system_time: System.system_time()},
      %{
        annotation: annotation,
        data: data,
        sha: sha,
        author: session.config.author
      }
    )

    {updated, Ref.act(sha)}
  end

  @spec decide(t(), String.t(), Ref.t(), String.t(), [String.t()]) :: {t(), Ref.t()}
  def decide(%__MODULE__{} = session, annotation, obs_ref, rule, act_shas) do
    obs_sha = Ref.sha(obs_ref)
    children_sha = Enum.join(act_shas)
    content = obs_sha <> rule <> children_sha
    sha = :bias.hash(content)
    entry = %{kind: :dec, data: rule, children: act_shas, annotation: annotation}

    updated = %{
      session
      | store: session.store ++ [{sha, entry}],
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
        author: session.config.author
      }
    )

    {updated, Ref.dec(sha)}
  end

  @spec observe(t(), String.t(), String.t(), String.t(), [String.t()]) :: {t(), Ref.t()}
  def observe(%__MODULE__{} = session, annotation, ref, data, decision_shas) do
    children_sha = Enum.join(decision_shas)
    content = ref <> data <> children_sha
    sha = :bias.hash(content)
    entry = %{kind: :obs, data: data, children: decision_shas, annotation: annotation}

    updated = %{
      session
      | store: session.store ++ [{sha, entry}],
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
        author: session.config.author
      }
    )

    {updated, Ref.obs(sha)}
  end

  @spec commit(t(), String.t(), [String.t()]) :: {t(), entry(), String.t()}
  def commit(%__MODULE__{} = session, annotation, observation_shas) do
    name = session.config.name
    children_sha = Enum.join(observation_shas)
    content = name <> children_sha
    sha = :bias.hash(content)
    entry = %{kind: :root, data: name, children: observation_shas, annotation: annotation}

    updated = %{
      session
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
        author: session.config.author
      }
    )

    {updated, entry, sha}
  end
end
