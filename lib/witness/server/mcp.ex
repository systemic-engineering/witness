defmodule Witness.Server.MCP do
  @moduledoc """
  MCP server for Witness observability.

  Exposes the local Witness event store and ODA session over the Model Context
  Protocol (MCP) 2024-11-05 via JSON-RPC 2.0 over stdio. AI agents can observe,
  decide, act, and query telemetry — all content-addressed.

  ## Usage

  Start via `Witness.Server` (recommended) or standalone for testing:

      {:ok, io} = StringIO.open(request <> "\\n")
      Witness.Server.MCP.run(io)

  ## Supported methods

    - `initialize`                — capability negotiation + session creation
    - `notifications/initialized` — client ready (no-op)
    - `tools/list`                — list available tools
    - `tools/call`                — call a tool
    - `ping`                      — liveness check

  ## Tools

    - `bias`        — ODA cascade (observe, optionally decide, optionally act)
    - `commit`      — seal session, wrap observations into root
    - `list_events` — query telemetry events from Mnesia store
  """

  alias Witness.Session
  alias Witness.Session.Ref

  @server_info %{name: "witness-mcp", version: "0.2.0"}
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
    loop(io_device, nil)
  end

  # ---------------------------------------------------------------------------
  # Loop — threads session state
  # ---------------------------------------------------------------------------

  defp loop(io_device, session) do
    case IO.read(io_device, :line) do
      :eof ->
        :ok

      {:error, _} ->
        :ok

      line when is_binary(line) ->
        {response, session} = handle_line(String.trim(line), session)
        if response, do: IO.write(io_device, response)
        loop(io_device, session)
    end
  end

  defp handle_line("", session), do: {nil, session}

  defp handle_line(line, session) do
    case JSON.decode(line) do
      {:ok, %{"id" => _} = msg} -> handle_request(msg, session)
      {:ok, _msg} -> {nil, session}
      {:error, _} -> {encode_error(nil, @parse_error, "Parse error"), session}
    end
  end

  # ---------------------------------------------------------------------------
  # Request dispatch
  # ---------------------------------------------------------------------------

  defp handle_request(%{"method" => "initialize", "id" => id} = msg, _session) do
    params = Map.get(msg, "params", %{})
    client_info = Map.get(params, "clientInfo", %{})
    name = Map.get(client_info, "name", "witness-mcp")

    session = Session.new(%{author: name, name: name})

    response =
      encode_result(id, %{
        protocolVersion: @protocol_version,
        capabilities: %{tools: %{}},
        serverInfo: @server_info
      })

    {response, session}
  end

  defp handle_request(%{"method" => "tools/list", "id" => id}, session) do
    {encode_result(id, %{tools: tools()}), session}
  end

  defp handle_request(%{"method" => "tools/call", "id" => id} = msg, session) do
    params = Map.get(msg, "params", %{})
    name = Map.get(params, "name")
    args = Map.get(params, "arguments", %{})

    {result, session} = dispatch(name, args, session)
    {encode_result(id, tool_result(result)), session}
  end

  defp handle_request(%{"method" => "ping", "id" => id}, session) do
    {encode_result(id, %{}), session}
  end

  defp handle_request(%{"method" => method, "id" => id}, session) do
    {encode_error(id, @method_not_found, "Method not found: #{method}"), session}
  end

  defp handle_request(%{"id" => id}, session) do
    {encode_error(id, @invalid_request, "Missing method"), session}
  end

  # ---------------------------------------------------------------------------
  # Tool dispatch
  # ---------------------------------------------------------------------------

  defp dispatch("bias", args, session) do
    session = session || Session.new(%{author: "unknown", name: "witness-mcp"})
    dispatch_bias(args, session)
  end

  defp dispatch("commit", args, session) do
    session = session || Session.new(%{author: "unknown", name: "witness-mcp"})
    dispatch_commit(args, session)
  end

  defp dispatch("list_events", args, session) do
    opts = build_query_opts(args)

    result =
      case Witness.Store.Mnesia.list_events(Witness.Server, opts, []) do
        {:ok, events} -> format_events(events)
        {:error, reason} -> {:error, "Store error: #{inspect(reason)}"}
      end

    {result, session}
  end

  defp dispatch(name, _args, session) when is_binary(name) do
    {{:error, "Unknown tool: #{name}"}, session}
  end

  defp dispatch(nil, _args, session) do
    {{:error, "Missing tool name"}, session}
  end

  # ---------------------------------------------------------------------------
  # Bias — single ODA call, cascading constraint
  # ---------------------------------------------------------------------------

  defp dispatch_bias(args, session) do
    annotation = Map.get(args, "annotation", "@signal")
    observation = Map.get(args, "observation", %{})
    decision = Map.get(args, "decision")
    action = Map.get(args, "action")

    obs_ref = Map.get(observation, "ref", "")
    obs_payload = Map.get(observation, "payload", "")

    # Cascade constraint: action requires decision
    if action && !decision do
      {{:error, "Action requires a decision. Provide decision before action."}, session}
    else
      # Bottom-up: act → decide → observe
      {session, result} = build_oda(session, annotation, obs_ref, obs_payload, decision, action)
      {{:ok, JSON.encode!(result)}, session}
    end
  end

  defp build_oda(session, annotation, obs_ref, obs_payload, decision, action) do
    # Act (if present)
    {session, act_sha, act_shas} =
      case action do
        %{"payload" => payload} ->
          act_ann = Map.get(action, "annotation", annotation)
          {s, ref} = Session.act(session, act_ann, payload)
          {s, Ref.sha(ref), [Ref.sha(ref)]}

        _ ->
          {session, nil, []}
      end

    # Decide (if present)
    {session, dec_sha, dec_shas} =
      case decision do
        %{"payload" => payload} ->
          dec_ann = Map.get(decision, "annotation", annotation)
          # Decision links to a placeholder obs ref — the observation is built after
          obs_placeholder = Ref.obs(:bias.hash(obs_ref <> obs_payload))
          {s, ref} = Session.decide(session, dec_ann, obs_placeholder, payload, act_shas)
          {s, Ref.sha(ref), [Ref.sha(ref)]}

        _ ->
          {session, nil, []}
      end

    # Observe (always)
    {session, obs_ref_result} = Session.observe(session, annotation, obs_ref, obs_payload, dec_shas)
    obs_sha = Ref.sha(obs_ref_result)

    result =
      %{obs_sha: obs_sha}
      |> maybe_add(:dec_sha, dec_sha)
      |> maybe_add(:act_sha, act_sha)

    {session, result}
  end

  defp maybe_add(map, _key, nil), do: map
  defp maybe_add(map, key, value), do: Map.put(map, key, value)

  # ---------------------------------------------------------------------------
  # Commit — seal session
  # ---------------------------------------------------------------------------

  defp dispatch_commit(args, session) do
    annotation = Map.get(args, "annotation", "@commit")

    {session, _root, root_sha} = Session.commit(session, annotation, [])

    # Reset session after commit (fresh state, same config)
    new_session = Session.new(Session.config(session))

    {{:ok, JSON.encode!(%{root_sha: root_sha})}, new_session}
  end

  # ---------------------------------------------------------------------------
  # Query helpers
  # ---------------------------------------------------------------------------

  defp build_query_opts(args) do
    []
    |> maybe_put(:limit, Map.get(args, "limit"))
    |> maybe_put(:after, Map.get(args, "after"))
    |> maybe_put(:before, Map.get(args, "before"))
    |> maybe_put(:event_name, parse_event_name(Map.get(args, "event_name")))
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp parse_event_name(nil), do: nil
  defp parse_event_name(parts) when is_list(parts), do: Enum.map(parts, &String.to_atom/1)
  defp parse_event_name(name) when is_binary(name), do: [String.to_atom(name)]

  defp format_events(events) do
    lines =
      Enum.map(events, fn event ->
        name = Enum.join(event.event_name, ".")
        attrs = inspect(event.attributes, limit: 5)
        "#{name} | #{attrs}"
      end)

    case lines do
      [] -> {:ok, "No events recorded."}
      _ -> {:ok, Enum.join(lines, "\n")}
    end
  end

  # ---------------------------------------------------------------------------
  # Tool definitions
  # ---------------------------------------------------------------------------

  defp tools do
    [
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
      },
      %{
        name: "commit",
        description: "Seal the session. Wraps observations into root entry.",
        inputSchema: %{
          type: "object",
          properties: %{
            annotation: %{type: "string", description: "Signal kind for the commit."}
          },
          required: ["annotation"]
        }
      },
      %{
        name: "list_events",
        description: "List telemetry events recorded by Witness. Returns event names and attributes.",
        inputSchema: %{
          type: "object",
          properties: %{
            limit: %{type: "integer", description: "Max events to return (default: all)"},
            after: %{
              type: "integer",
              description: "Only events after this timestamp (microseconds)"
            },
            before: %{
              type: "integer",
              description: "Only events before this timestamp (microseconds)"
            },
            event_name: %{
              type: "array",
              items: %{type: "string"},
              description: "Filter by event name parts (e.g. [\"glue\", \"dispatch\", \"start\"])"
            }
          },
          required: []
        }
      }
    ]
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
