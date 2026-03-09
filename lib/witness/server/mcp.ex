defmodule Witness.Server.MCP do
  @moduledoc """
  MCP server for Witness observability.

  State machine driven by `Witness.Actor`. The tool surface changes based on
  session lifecycle:

    - `:uninitialized` → tools = [`init`]
    - `{:active, actor}` → tools = [`bias`, `query`, `exit`]

  Transitions emit `notifications/tools/list_changed` so the client discovers
  the new surface.

  ## Usage

  Start via `Witness.Server` (recommended) or standalone for testing:

      {:ok, io} = StringIO.open(request <> "\\n")
      Witness.Server.MCP.run(io)

  ## Supported methods

    - `initialize`                — capability negotiation
    - `notifications/initialized` — client ready (no-op)
    - `tools/list`                — list available tools (state-dependent)
    - `tools/call`                — call a tool (state-gated)
    - `ping`                      — liveness check
  """

  alias Witness.Actor
  alias Witness.Event

  @server_info %{name: "witness-mcp", version: "0.3.0"}
  @protocol_version "2024-11-05"

  @parse_error -32_700
  @method_not_found -32_601
  @invalid_request -32_600

  @doc """
  Run the MCP server against a custom IO device (for testing or piped use).
  Reads line-by-line until EOF, writing JSON-RPC responses back to the device.
  """
  @spec run(IO.device()) :: :ok
  def run(io_device) do
    loop(io_device, :uninitialized)
  end

  # ---------------------------------------------------------------------------
  # Loop — threads state machine
  # ---------------------------------------------------------------------------

  defp loop(io_device, state) do
    case IO.read(io_device, :line) do
      :eof ->
        :ok

      {:error, _} ->
        :ok

      line when is_binary(line) ->
        {responses, state} = handle_line(String.trim(line), state)
        for response <- List.wrap(responses), do: IO.write(io_device, response)
        loop(io_device, state)
    end
  end

  defp handle_line("", state), do: {nil, state}

  defp handle_line(line, state) do
    case JSON.decode(line) do
      {:ok, %{"id" => _} = msg} -> handle_request(msg, state)
      {:ok, _msg} -> {nil, state}
      {:error, _} -> {encode_error(nil, @parse_error, "Parse error"), state}
    end
  end

  # ---------------------------------------------------------------------------
  # Request dispatch
  # ---------------------------------------------------------------------------

  defp handle_request(%{"method" => "initialize", "id" => id}, state) do
    response =
      encode_result(id, %{
        protocolVersion: @protocol_version,
        capabilities: %{tools: %{}},
        serverInfo: @server_info
      })

    {response, state}
  end

  defp handle_request(%{"method" => "tools/list", "id" => id}, state) do
    {encode_result(id, %{tools: tools_for(state)}), state}
  end

  defp handle_request(%{"method" => "tools/call", "id" => id} = msg, state) do
    params = Map.get(msg, "params", %{})
    name = Map.get(params, "name")
    args = Map.get(params, "arguments", %{})

    {result, state, notifications} = dispatch(name, args, state)
    responses = notifications ++ [encode_result(id, tool_result(result))]
    {responses, state}
  end

  defp handle_request(%{"method" => "ping", "id" => id}, state) do
    {encode_result(id, %{}), state}
  end

  defp handle_request(%{"method" => method, "id" => id}, state) do
    {encode_error(id, @method_not_found, "Method not found: #{method}"), state}
  end

  defp handle_request(%{"id" => id}, state) do
    {encode_error(id, @invalid_request, "Missing method"), state}
  end

  # ---------------------------------------------------------------------------
  # Tool dispatch — state-gated
  # ---------------------------------------------------------------------------

  defp dispatch("init", args, :uninitialized) do
    name = Map.get(args, "name", "anonymous")
    email = Map.get(args, "email", "#{name}@witness")

    actor = Actor.new(name: name, email: email, repo: Witness.DefaultRepo)
    identity = Actor.identity(actor)

    obs = %{"ref" => "init", "payload" => JSON.encode!(identity)}
    {actor, %{obs_sha: obs_sha}} = Actor.bias(actor, "@init", obs, nil, nil)

    result = {:ok, JSON.encode!(Map.put(identity, :obs_sha, obs_sha))}
    {{:active, actor}, notifications} = transition({:active, actor})
    {result, {:active, actor}, notifications}
  end

  defp dispatch("bias", args, {:active, actor}) do
    annotation = Map.get(args, "annotation", "@signal")
    observation = Map.get(args, "observation", %{})
    decision = Map.get(args, "decision")
    action = Map.get(args, "action")

    {actor, result} = Actor.bias(actor, annotation, observation, decision, action)

    case result do
      {:error, reason} ->
        {{:error, reason}, {:active, actor}, []}

      shas ->
        {{:ok, JSON.encode!(shas)}, {:active, actor}, []}
    end
  end

  defp dispatch("query", args, {:active, actor}) do
    result =
      cond do
        Map.get(args, "head") ->
          case actor.head do
            nil -> {:error, "No commits yet"}
            sha -> query_sha(actor, sha)
          end

        sha = Map.get(args, "sha") ->
          query_sha(actor, sha)

        true ->
          {:error, "Provide sha or head:true"}
      end

    {result, {:active, actor}, []}
  end

  defp dispatch("exit", args, {:active, actor}) do
    annotation = Map.get(args, "annotation", "@exit")
    {_actor, root_sha} = Actor.seal(actor, annotation)

    result = {:ok, JSON.encode!(%{root_sha: root_sha})}
    {:uninitialized, notifications} = transition(:uninitialized)
    {result, :uninitialized, notifications}
  end

  # State-gated errors
  defp dispatch("init", _args, {:active, actor}) do
    {{:error, "Already initialized"}, {:active, actor}, []}
  end

  defp dispatch(name, _args, :uninitialized) when name in ~w(bias query exit) do
    {{:error, "Not initialized. Call init first."}, :uninitialized, []}
  end

  defp dispatch(name, _args, state) when is_binary(name) do
    {{:error, "Unknown tool: #{name}"}, state, []}
  end

  defp dispatch(nil, _args, state) do
    {{:error, "Missing tool name"}, state, []}
  end

  # ---------------------------------------------------------------------------
  # Query helper
  # ---------------------------------------------------------------------------

  defp query_sha(actor, sha) do
    case actor.repo.get(Event, sha) do
      nil -> {:error, "Event not found: #{sha}"}
      event -> {:ok, JSON.encode!(%{sha: event.sha, data: event.data, message: event.message, parent: event.parent})}
    end
  end

  # ---------------------------------------------------------------------------
  # State transitions — emit notifications
  # ---------------------------------------------------------------------------

  defp transition(new_state) do
    {new_state, [tools_changed_notification()]}
  end

  defp tools_changed_notification do
    JSON.encode!(%{jsonrpc: "2.0", method: "notifications/tools/list_changed"}) <> "\n"
  end

  # ---------------------------------------------------------------------------
  # Tool definitions — state-dependent
  # ---------------------------------------------------------------------------

  defp tools_for(:uninitialized), do: [init_tool()]
  defp tools_for({:active, _}), do: [bias_tool(), query_tool(), exit_tool()]

  defp init_tool do
    %{
      name: "init",
      description: "Initialize the Witness session. Establishes actor identity.",
      inputSchema: %{
        type: "object",
        properties: %{
          name: %{type: "string", description: "Actor name."},
          email: %{type: "string", description: "Actor email."}
        },
        required: ["name"]
      }
    }
  end

  defp bias_tool do
    %{
      name: "bias",
      description:
        "Observation filtered through subjectivity, made structural. Observe first. Decide from observation. Act from decision.",
      inputSchema: %{
        type: "object",
        properties: %{
          annotation: %{type: "string", description: "Signal kind. What drain filters on."},
          observation: %{
            type: "object",
            properties: %{
              ref: %{type: "string", description: "Where you observed it."},
              payload: %{type: "string", description: "What you observed."}
            },
            required: ["ref", "payload"]
          },
          decision: %{
            type: "object",
            properties: %{
              annotation: %{type: "string", description: "Signal kind for the decision."},
              payload: %{type: "string", description: "What you concluded from observation."}
            },
            required: ["payload"]
          },
          action: %{
            type: "object",
            properties: %{
              annotation: %{type: "string", description: "Signal kind for the action."},
              payload: %{type: "string", description: "The action taken."}
            },
            required: ["payload"]
          }
        },
        required: ["annotation", "observation"]
      }
    }
  end

  defp query_tool do
    %{
      name: "query",
      description: "Query a commit by SHA, or get the current head.",
      inputSchema: %{
        type: "object",
        properties: %{
          sha: %{type: "string", description: "Commit SHA to look up."},
          head: %{type: "boolean", description: "If true, return the current head commit."}
        }
      }
    }
  end

  defp exit_tool do
    %{
      name: "exit",
      description: "Seal the session. Creates closing commit, returns root SHA, resets to uninitialized.",
      inputSchema: %{
        type: "object",
        properties: %{
          annotation: %{type: "string", description: "Signal kind for the closing commit."}
        },
        required: ["annotation"]
      }
    }
  end

  # ---------------------------------------------------------------------------
  # JSON-RPC helpers
  # ---------------------------------------------------------------------------

  defp encode_result(id, result) do
    JSON.encode!(%{jsonrpc: "2.0", id: id, result: result}) <> "\n"
  end

  defp encode_error(id, code, message) do
    JSON.encode!(%{jsonrpc: "2.0", id: id, error: %{code: code, message: message}}) <> "\n"
  end

  defp tool_result({:ok, text}), do: %{content: [%{type: "text", text: text}], isError: false}
  defp tool_result({:error, text}), do: %{content: [%{type: "text", text: text}], isError: true}
end
