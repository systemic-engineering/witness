defmodule Witness.Session do
  @moduledoc """
  Session GenServer — the server.

  A session is a process group. Actors join it, their PIDs are the
  participants. When all participants leave (or die), a grace timer
  starts. If no one rejoins before grace expires, the session auto-seals
  and stops.

  The ODA cascade runs inside the session. `bias/5` and `seal/2` are
  GenServer calls that thread the pure `Session.State` internally.

  ## Struct-based API (backward compat)

  `new/1`, `act/3`, `decide/5`, `observe/5`, `commit/3` delegate to
  `Session.State` for callers that still use `%Session{}` directly.
  These will be removed once Actor and MCP are rewired (Phase 2).
  """

  use GenServer

  alias Witness.Event
  alias Witness.Session.Ref
  alias Witness.Session.State

  @default_grace_ms 5_000

  @type t :: %__MODULE__{
          config: State.config(),
          store: [{String.t(), State.entry()}],
          last_root: {State.entry(), String.t()} | nil,
          head: String.t()
        }

  @type config :: State.config()
  @type entry :: State.entry()

  defstruct config: %{author: "", name: ""},
            store: [],
            last_root: nil,
            head: ""

  # ---------------------------------------------------------------------------
  # Struct-based delegation (backward compat — Phase 2 removes these)
  # ---------------------------------------------------------------------------

  defdelegate new(config), to: State
  defdelegate config(session_struct), to: State
  defdelegate last_root(session_struct), to: State
  defdelegate act(session_struct, annotation, data), to: State
  defdelegate decide(session_struct, annotation, obs_ref, rule, act_shas), to: State
  defdelegate observe(session_struct, annotation, ref, data, decision_shas), to: State
  defdelegate commit(session_struct, annotation, observation_shas), to: State

  @doc """
  Returns the head SHA.

  Accepts either a `%Session{}` struct or a session PID.
  """
  def head(%__MODULE__{} = session_struct), do: State.head(session_struct)
  def head(pid) when is_pid(pid), do: GenServer.call(pid, :head)

  # ---------------------------------------------------------------------------
  # GenServer API — the server
  # ---------------------------------------------------------------------------

  @doc """
  Start a session process.

  ## Options

    * `:name` — session name (required)
    * `:author` — session author (required)
    * `:repos` — list of repo modules for persistence (default: `[]`)
    * `:grace_ms` — grace period in ms before auto-seal (default: `#{@default_grace_ms}`)
  """
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    author = Keyword.fetch!(opts, :author)
    repos = Keyword.get(opts, :repos, [])
    grace_ms = Keyword.get(opts, :grace_ms, @default_grace_ms)

    GenServer.start_link(__MODULE__, %{
      name: name,
      author: author,
      repos: repos,
      grace_ms: grace_ms
    })
  end

  @doc "Join the session. The calling process is monitored."
  def join(pid, identity \\ nil) do
    GenServer.call(pid, {:join, self(), identity})
  end

  @doc "Leave the session explicitly."
  def leave(pid) do
    GenServer.call(pid, {:leave, self()})
  end

  @doc "List participant PIDs."
  def participants(pid) do
    GenServer.call(pid, :participants)
  end

  @doc """
  Run an ODA cascade.

  Returns `{:ok, result}` where result is a map of SHAs,
  or `{:error, reason}`.
  """
  def bias(pid, annotation, observation, decision, action) do
    GenServer.call(pid, {:bias, annotation, observation, decision, action})
  end

  @doc """
  Seal the session with a closing commit.

  Returns `{:ok, root_sha}`.
  """
  def seal(pid, annotation) do
    GenServer.call(pid, {:seal, annotation})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(%{name: name, author: author, repos: repos, grace_ms: grace_ms}) do
    oda = State.new(%{author: author, name: name})

    {:ok,
     %{
       oda: oda,
       repos: repos,
       participants: %{},
       head: nil,
       grace_timer: nil,
       grace_ms: grace_ms
     }}
  end

  @impl true
  def handle_call({:join, pid, identity}, _from, state) do
    if Map.has_key?(state.participants, pid) do
      {:reply, :ok, state}
    else
      ref = Process.monitor(pid)
      state = cancel_grace(state)
      participants = Map.put(state.participants, pid, {ref, identity})
      {:reply, :ok, %{state | participants: participants}}
    end
  end

  def handle_call({:leave, pid}, _from, state) do
    state = remove_participant(state, pid)
    state = maybe_start_grace(state)
    {:reply, :ok, state}
  end

  def handle_call(:participants, _from, state) do
    {:reply, Map.keys(state.participants), state}
  end

  def handle_call(:head, _from, state) do
    {:reply, state.head, state}
  end

  def handle_call({:bias, annotation, observation, decision, action}, _from, state) do
    if action && !decision do
      {:reply, {:error, "Action requires a decision"}, state}
    else
      {oda, head, result} =
        do_bias(state.oda, state.repos, state.head, annotation, observation, decision, action)

      {:reply, {:ok, result}, %{state | oda: oda, head: head}}
    end
  end

  def handle_call({:seal, annotation}, _from, state) do
    {oda, head, root_sha} = do_seal(state.oda, state.repos, state.head, annotation)
    {:reply, {:ok, root_sha}, %{state | oda: oda, head: head}}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    state = remove_participant(state, pid)
    state = maybe_start_grace(state)
    {:noreply, state}
  end

  def handle_info(:grace_expired, state) do
    if map_size(state.participants) == 0 do
      {_oda, _head, _root_sha} = do_seal(state.oda, state.repos, state.head, "@grace_timeout")
      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end

  # ---------------------------------------------------------------------------
  # Private — participant lifecycle
  # ---------------------------------------------------------------------------

  defp remove_participant(state, pid) do
    case Map.pop(state.participants, pid) do
      {{ref, _identity}, participants} ->
        Process.demonitor(ref, [:flush])
        %{state | participants: participants}

      {nil, _} ->
        state
    end
  end

  defp maybe_start_grace(%{participants: participants, grace_ms: grace_ms} = state)
       when map_size(participants) == 0 do
    timer = Process.send_after(self(), :grace_expired, grace_ms)
    %{state | grace_timer: timer}
  end

  defp maybe_start_grace(state), do: state

  defp cancel_grace(%{grace_timer: nil} = state), do: state

  defp cancel_grace(%{grace_timer: timer} = state) do
    Process.cancel_timer(timer)
    %{state | grace_timer: nil}
  end

  # ---------------------------------------------------------------------------
  # Private — ODA cascade (moved from Actor)
  # ---------------------------------------------------------------------------

  defp do_bias(oda, repos, head, annotation, observation, decision, action) do
    obs_ref = Map.get(observation, "ref", "")
    obs_payload = Map.get(observation, "payload", "")

    {oda, head, act_sha, act_shas} = maybe_act(oda, repos, head, annotation, action)

    {oda, head, dec_sha, dec_shas} =
      maybe_decide(oda, repos, head, annotation, obs_ref, obs_payload, decision, act_shas)

    {oda, head, obs_sha} = do_observe(oda, repos, head, annotation, obs_ref, obs_payload, dec_shas)

    result =
      %{obs_sha: obs_sha}
      |> maybe_put(:dec_sha, dec_sha)
      |> maybe_put(:act_sha, act_sha)

    {oda, head, result}
  end

  defp maybe_act(oda, _repos, head, _annotation, nil), do: {oda, head, nil, []}

  defp maybe_act(oda, repos, head, annotation, %{"payload" => payload} = action) do
    act_ann = Map.get(action, "annotation", annotation)
    {oda, ref} = State.act(oda, act_ann, payload)
    sha = Ref.sha(ref)

    data = JSON.encode!(%{kind: :act, payload: payload, annotation: act_ann})
    persist(repos, head, sha, data, act_ann)

    {oda, sha, sha, [sha]}
  end

  defp maybe_decide(oda, _repos, head, _annotation, _obs_ref, _obs_payload, nil, _act_shas),
    do: {oda, head, nil, []}

  defp maybe_decide(
         oda,
         repos,
         head,
         annotation,
         obs_ref,
         obs_payload,
         %{"payload" => payload} = decision,
         act_shas
       ) do
    dec_ann = Map.get(decision, "annotation", annotation)
    obs_placeholder = Ref.obs(:bias.hash(obs_ref <> obs_payload))
    {oda, ref} = State.decide(oda, dec_ann, obs_placeholder, payload, act_shas)
    sha = Ref.sha(ref)

    data =
      JSON.encode!(%{kind: :dec, payload: payload, annotation: dec_ann, act_shas: act_shas})

    persist(repos, head, sha, data, dec_ann)

    {oda, sha, sha, [sha]}
  end

  defp do_observe(oda, repos, head, annotation, obs_ref, obs_payload, dec_shas) do
    {oda, ref} = State.observe(oda, annotation, obs_ref, obs_payload, dec_shas)
    sha = Ref.sha(ref)

    data =
      JSON.encode!(%{
        kind: :obs,
        ref: obs_ref,
        payload: obs_payload,
        annotation: annotation,
        dec_shas: dec_shas
      })

    persist(repos, head, sha, data, annotation)

    {oda, sha, sha}
  end

  defp do_seal(oda, repos, head, annotation) do
    obs_shas =
      oda.store
      |> Enum.filter(fn {_sha, entry} -> entry.kind == :obs end)
      |> Enum.map(fn {sha, _entry} -> sha end)

    {oda, _entry, root_sha} = State.commit(oda, annotation, obs_shas)

    root_data =
      JSON.encode!(%{kind: :root, name: oda.config.name, observation_shas: obs_shas})

    persist(repos, head, root_sha, root_data, annotation)

    new_oda = State.new(State.config(oda))
    {new_oda, root_sha, root_sha}
  end

  defp persist([repo | _], parent, sha, data, message) do
    event = %Event{sha: sha, data: data, message: message, parent: parent}
    repo.insert(event)
  end

  defp persist([], _parent, _sha, _data, _message), do: :ok

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
