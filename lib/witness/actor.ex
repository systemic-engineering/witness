defmodule Witness.Actor do
  @moduledoc """
  Representation of the agent calling Witness MCP tools.

  A Fragmentation concept: the Actor has identity, a session, and a Repo.
  Each `bias/5` call builds an ODA cascade via `Witness.Session` and
  persists each entry as a `Witness.Event` via `Repo.insert/1`.
  The commit chain is linked through parent SHAs.

  ## Usage

      actor = Witness.Actor.new(name: "reed", email: "reed@systemic.engineer", repo: MyRepo)
      {actor, %{obs_sha: sha}} = Witness.Actor.bias(actor, "@signal", obs, nil, nil)
      {actor, root_sha} = Witness.Actor.seal(actor, "@exit")
  """

  alias Witness.Event
  alias Witness.Session
  alias Witness.Session.Ref

  @enforce_keys [:name, :repo]
  defstruct [:name, :email, :repo, :session, :head]

  @type t :: %__MODULE__{
          name: String.t(),
          email: String.t() | nil,
          repo: module(),
          session: Session.t(),
          head: String.t() | nil
        }

  @spec new(keyword()) :: t()
  def new(opts) do
    name = Keyword.fetch!(opts, :name)
    email = Keyword.get(opts, :email, "#{name}@witness")
    repo = Keyword.fetch!(opts, :repo)
    session = Session.new(%{author: email, name: name})

    %__MODULE__{
      name: name,
      email: email,
      repo: repo,
      session: session,
      head: nil
    }
  end

  @spec identity(t()) :: %{name: String.t(), email: String.t()}
  def identity(%__MODULE__{name: name, email: email}) do
    %{name: name, email: email}
  end

  @doc """
  Run an ODA cascade and persist each entry as a commit.

  Returns `{updated_actor, result}` where result is a map of SHAs
  or `{:error, reason}`.
  """
  @spec bias(t(), String.t(), map(), map() | nil, map() | nil) ::
          {t(), map() | {:error, String.t()}}
  def bias(%__MODULE__{} = actor, annotation, observation, decision, action) do
    if action && !decision do
      {actor, {:error, "Action requires a decision"}}
    else
      do_bias(actor, annotation, observation, decision, action)
    end
  end

  @doc """
  Seal the session with a closing commit.

  Returns `{updated_actor, root_sha}`.
  """
  @spec seal(t(), String.t()) :: {t(), String.t()}
  def seal(%__MODULE__{} = actor, annotation) do
    obs_shas =
      actor.session.store
      |> Enum.filter(fn {_sha, entry} -> entry.kind == :obs end)
      |> Enum.map(fn {sha, _entry} -> sha end)

    {session, _entry, root_sha} = Session.commit(actor.session, annotation, obs_shas)

    root_data = JSON.encode!(%{kind: :root, name: actor.name, observation_shas: obs_shas})
    persist(actor, root_sha, root_data, annotation)

    actor = %{actor | session: Session.new(Session.config(session)), head: root_sha}
    {actor, root_sha}
  end

  # ---------------------------------------------------------------------------
  # Private — ODA cascade + persistence
  # ---------------------------------------------------------------------------

  defp do_bias(actor, annotation, observation, decision, action) do
    obs_ref = Map.get(observation, "ref", "")
    obs_payload = Map.get(observation, "payload", "")

    # Bottom-up: act → decide → observe
    {actor, act_sha, act_shas} = maybe_act(actor, annotation, action)
    {actor, dec_sha, dec_shas} = maybe_decide(actor, annotation, obs_ref, obs_payload, decision, act_shas)
    {actor, obs_sha} = do_observe(actor, annotation, obs_ref, obs_payload, dec_shas)

    result =
      %{obs_sha: obs_sha}
      |> maybe_put(:dec_sha, dec_sha)
      |> maybe_put(:act_sha, act_sha)

    {actor, result}
  end

  defp maybe_act(actor, _annotation, nil), do: {actor, nil, []}

  defp maybe_act(actor, annotation, %{"payload" => payload} = action) do
    act_ann = Map.get(action, "annotation", annotation)
    {session, ref} = Session.act(actor.session, act_ann, payload)
    sha = Ref.sha(ref)

    data = JSON.encode!(%{kind: :act, payload: payload, annotation: act_ann})
    actor = %{actor | session: session}
    persist(actor, sha, data, act_ann)

    {%{actor | head: sha}, sha, [sha]}
  end

  defp maybe_decide(actor, _annotation, _obs_ref, _obs_payload, nil, _act_shas),
    do: {actor, nil, []}

  defp maybe_decide(actor, annotation, obs_ref, obs_payload, %{"payload" => payload} = decision, act_shas) do
    dec_ann = Map.get(decision, "annotation", annotation)
    obs_placeholder = Ref.obs(:bias.hash(obs_ref <> obs_payload))
    {session, ref} = Session.decide(actor.session, dec_ann, obs_placeholder, payload, act_shas)
    sha = Ref.sha(ref)

    data = JSON.encode!(%{kind: :dec, payload: payload, annotation: dec_ann, act_shas: act_shas})
    actor = %{actor | session: session}
    persist(actor, sha, data, dec_ann)

    {%{actor | head: sha}, sha, [sha]}
  end

  defp do_observe(actor, annotation, obs_ref, obs_payload, dec_shas) do
    {session, ref} = Session.observe(actor.session, annotation, obs_ref, obs_payload, dec_shas)
    sha = Ref.sha(ref)

    data = JSON.encode!(%{kind: :obs, ref: obs_ref, payload: obs_payload, annotation: annotation, dec_shas: dec_shas})
    actor = %{actor | session: session}
    persist(actor, sha, data, annotation)

    {%{actor | head: sha}, sha}
  end

  defp persist(%__MODULE__{repo: repo, head: parent}, sha, data, message) do
    event = %Event{sha: sha, data: data, message: message, parent: parent}
    repo.insert(event)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
