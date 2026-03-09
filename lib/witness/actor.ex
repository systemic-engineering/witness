defmodule Witness.Actor do
  @moduledoc """
  GenServer per witnessed module + ODA cascade functions.

  The Actor is the process that holds a live `%Witness{}` struct, registered
  in `Witness.Registry` for lookup by module atom. It also provides `bias/5`
  and `seal/2` for running ODA cascades against any `%Witness{}`.

  ## GenServer

      {:ok, pid} = Witness.Actor.start_link(MyApp.Context)
      witness = GenServer.call(pid, :__witness__)

  ## ODA

      witness = %Witness{identity: identity, session: session, repos: [repo], ...}
      {witness, %{obs_sha: sha}} = Witness.Actor.bias(witness, "@signal", obs, nil, nil)
      {witness, root_sha} = Witness.Actor.seal(witness, "@exit")
  """

  use GenServer

  alias Witness.Event
  alias Witness.Session
  alias Witness.Session.Ref

  # ---------------------------------------------------------------------------
  # GenServer
  # ---------------------------------------------------------------------------

  @doc "Start and register an Actor for the given witnessed module."
  def start_link(module) do
    GenServer.start_link(__MODULE__, module, name: {:via, Registry, {Witness.Registry, module}})
  end

  @impl true
  def init(module) do
    witness = Witness.start(module)
    {:ok, witness}
  end

  @impl true
  def handle_call(:__witness__, _from, witness) do
    {:reply, witness, witness}
  end

  # ---------------------------------------------------------------------------
  # ODA — bias/5 and seal/2 operate on %Witness{}
  # ---------------------------------------------------------------------------

  @doc """
  Run an ODA cascade and persist each entry as a commit.

  Returns `{updated_witness, result}` where result is a map of SHAs
  or `{:error, reason}`.
  """
  @spec bias(Witness.witness(), String.t(), map(), map() | nil, map() | nil) ::
          {Witness.witness(), map() | {:error, String.t()}}
  def bias(%Witness{} = witness, annotation, observation, decision, action) do
    if action && !decision do
      {witness, {:error, "Action requires a decision"}}
    else
      do_bias(witness, annotation, observation, decision, action)
    end
  end

  @doc """
  Seal the session with a closing commit.

  Returns `{updated_witness, root_sha}`.
  """
  @spec seal(Witness.witness(), String.t()) :: {Witness.witness(), String.t()}
  def seal(%Witness{} = witness, annotation) do
    obs_shas =
      witness.session.store
      |> Enum.filter(fn {_sha, entry} -> entry.kind == :obs end)
      |> Enum.map(fn {sha, _entry} -> sha end)

    {session, _entry, root_sha} = Session.commit(witness.session, annotation, obs_shas)

    identity_name = if witness.identity, do: witness.identity.name, else: "anonymous"
    root_data = JSON.encode!(%{kind: :root, name: identity_name, observation_shas: obs_shas})
    persist(witness, root_sha, root_data, annotation)

    witness = %{witness | session: Session.new(Session.config(session)), head: root_sha}
    {witness, root_sha}
  end

  # ---------------------------------------------------------------------------
  # Private — ODA cascade + persistence
  # ---------------------------------------------------------------------------

  defp do_bias(witness, annotation, observation, decision, action) do
    obs_ref = Map.get(observation, "ref", "")
    obs_payload = Map.get(observation, "payload", "")

    # Bottom-up: act → decide → observe
    {witness, act_sha, act_shas} = maybe_act(witness, annotation, action)
    {witness, dec_sha, dec_shas} = maybe_decide(witness, annotation, obs_ref, obs_payload, decision, act_shas)
    {witness, obs_sha} = do_observe(witness, annotation, obs_ref, obs_payload, dec_shas)

    result =
      %{obs_sha: obs_sha}
      |> maybe_put(:dec_sha, dec_sha)
      |> maybe_put(:act_sha, act_sha)

    {witness, result}
  end

  defp maybe_act(witness, _annotation, nil), do: {witness, nil, []}

  defp maybe_act(witness, annotation, %{"payload" => payload} = action) do
    act_ann = Map.get(action, "annotation", annotation)
    {session, ref} = Session.act(witness.session, act_ann, payload)
    sha = Ref.sha(ref)

    data = JSON.encode!(%{kind: :act, payload: payload, annotation: act_ann})
    witness = %{witness | session: session}
    persist(witness, sha, data, act_ann)

    {%{witness | head: sha}, sha, [sha]}
  end

  defp maybe_decide(witness, _annotation, _obs_ref, _obs_payload, nil, _act_shas),
    do: {witness, nil, []}

  defp maybe_decide(witness, annotation, obs_ref, obs_payload, %{"payload" => payload} = decision, act_shas) do
    dec_ann = Map.get(decision, "annotation", annotation)
    obs_placeholder = Ref.obs(:bias.hash(obs_ref <> obs_payload))
    {session, ref} = Session.decide(witness.session, dec_ann, obs_placeholder, payload, act_shas)
    sha = Ref.sha(ref)

    data = JSON.encode!(%{kind: :dec, payload: payload, annotation: dec_ann, act_shas: act_shas})
    witness = %{witness | session: session}
    persist(witness, sha, data, dec_ann)

    {%{witness | head: sha}, sha, [sha]}
  end

  defp do_observe(witness, annotation, obs_ref, obs_payload, dec_shas) do
    {session, ref} = Session.observe(witness.session, annotation, obs_ref, obs_payload, dec_shas)
    sha = Ref.sha(ref)

    data = JSON.encode!(%{kind: :obs, ref: obs_ref, payload: obs_payload, annotation: annotation, dec_shas: dec_shas})
    witness = %{witness | session: session}
    persist(witness, sha, data, annotation)

    {%{witness | head: sha}, sha}
  end

  defp persist(%Witness{repos: [repo | _], head: parent}, sha, data, message) do
    event = %Event{sha: sha, data: data, message: message, parent: parent}
    repo.insert(event)
  end

  defp persist(%Witness{repos: []}, _sha, _data, _message), do: :ok

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
