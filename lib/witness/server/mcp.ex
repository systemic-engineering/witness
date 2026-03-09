defmodule Witness.Server.MCP do
  @moduledoc """
  MCP IO adapter for Witness sessions.

  Thin protocol translation layer — parses JSON-RPC, delegates to
  `Witness.Session` GenServer, formats responses. No state of its own
  beyond the session PID.

  State machine:
    - `:uninitialized` → tools = [`init`]
    - `{:active, session_pid}` → tools = [`bias`, `query`, `exit`]

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

  alias Witness.Session

  @server_info %{name: "witness-mcp", version: "0.4.0"}
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
  # Tool dispatch — state-gated, delegates to Session GenServer
  # ---------------------------------------------------------------------------

  defp dispatch("init", args, :uninitialized) do
    name = Map.get(args, "name", "anonymous")
    email = Map.get(args, "email", "#{name}@witness")

    {:ok, session_pid} =
      Session.start_link(
        name: name,
        author: email,
        repos: [Witness.InMemory]
      )

    identity = %Witness.Actor.Identity{name: name, email: email}
    Session.join(session_pid, identity)

    identity_map = %{name: name, email: email}
    obs = %{"ref" => "init", "payload" => JSON.encode!(identity_map)}
    {:ok, %{obs_sha: obs_sha}} = Session.bias(session_pid, "@init", obs, nil, nil)

    result = {:ok, JSON.encode!(Map.put(identity_map, :obs_sha, obs_sha))}
    {{:active, session_pid}, notifications} = transition({:active, session_pid})
    {result, {:active, session_pid}, notifications}
  end

  defp dispatch("bias", args, {:active, session_pid}) do
    annotation = Map.get(args, "annotation", "@signal")
    observation = Map.get(args, "observation", %{})
    decision = Map.get(args, "decision")
    action = Map.get(args, "action")

    case Session.bias(session_pid, annotation, observation, decision, action) do
      {:ok, shas} ->
        {{:ok, JSON.encode!(shas)}, {:active, session_pid}, []}

      {:error, reason} ->
        {{:error, reason}, {:active, session_pid}, []}
    end
  end

  defp dispatch("query", args, {:active, session_pid}) do
    result =
      cond do
        Map.get(args, "head") ->
          case Session.query(session_pid, :head) do
            {:ok, event} -> {:ok, format_event(event)}
            {:error, reason} -> {:error, reason}
          end

        sha = Map.get(args, "sha") ->
          case Session.query(session_pid, sha) do
            {:ok, event} -> {:ok, format_event(event)}
            {:error, reason} -> {:error, reason}
          end

        true ->
          {:error, "Provide sha or head:true"}
      end

    {result, {:active, session_pid}, []}
  end

  defp dispatch("exit", args, {:active, session_pid}) do
    annotation = Map.get(args, "annotation", "@exit")
    {:ok, root_sha} = Session.seal(session_pid, annotation)
    GenServer.stop(session_pid)

    result = {:ok, JSON.encode!(%{root_sha: root_sha})}
    {:uninitialized, notifications} = transition(:uninitialized)
    {result, :uninitialized, notifications}
  end

  # State-gated errors
  defp dispatch("init", _args, {:active, session_pid}) do
    {{:error, "Already initialized"}, {:active, session_pid}, []}
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
  # Event formatting
  # ---------------------------------------------------------------------------

  defp format_event(event) do
    JSON.encode!(%{
      sha: event.sha,
      data: event.data,
      message: event.message,
      parent: event.parent
    })
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
