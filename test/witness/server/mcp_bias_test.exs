defmodule Witness.Server.MCPBiasTest do
  use ExUnit.Case, async: false

  alias Witness.Server.MCP

  # Helper: send multiple JSON-RPC lines, return decoded responses
  defp run_session(lines) do
    input = Enum.join(lines, "\n") <> "\n"
    {:ok, io} = StringIO.open(input)
    MCP.run(io)
    {_input, output} = StringIO.contents(io)
    output |> String.split("\n", trim: true) |> Enum.map(&JSON.decode!/1)
  end

  defp init_line do
    ~s({"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test-agent","version":"0.1.0"}}})
  end

  defp bias_call(id, args) do
    args_json = JSON.encode!(args)

    ~s({"jsonrpc":"2.0","id":#{id},"method":"tools/call","params":{"name":"bias","arguments":#{args_json}}})
  end

  defp commit_call(id, args) do
    args_json = JSON.encode!(args)

    ~s({"jsonrpc":"2.0","id":#{id},"method":"tools/call","params":{"name":"commit","arguments":#{args_json}}})
  end

  describe "tools/list" do
    test "includes bias and commit tools" do
      responses =
        run_session([
          init_line(),
          ~s({"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}})
        ])

      tool_list_resp = Enum.find(responses, &(&1["id"] == 2))
      names = Enum.map(tool_list_resp["result"]["tools"], & &1["name"])
      assert "bias" in names
      assert "commit" in names
      assert "list_events" in names
    end

    test "bias tool has cascading input schema" do
      responses =
        run_session([
          init_line(),
          ~s({"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}})
        ])

      tool_list_resp = Enum.find(responses, &(&1["id"] == 2))
      bias_tool = Enum.find(tool_list_resp["result"]["tools"], &(&1["name"] == "bias"))
      schema = bias_tool["inputSchema"]

      assert schema["type"] == "object"
      assert "annotation" in schema["required"]
      assert "observation" in schema["required"]
      assert is_map(schema["properties"]["observation"])
      assert is_map(schema["properties"]["decision"])
      assert is_map(schema["properties"]["action"])
    end
  end

  describe "bias tool" do
    test "observation only — returns obs_sha" do
      responses =
        run_session([
          init_line(),
          bias_call(2, %{
            annotation: "@work",
            observation: %{ref: "file:lib/app.ex", payload: "checked types"}
          })
        ])

      resp = Enum.find(responses, &(&1["id"] == 2))
      assert resp["result"]["isError"] == false
      [content] = resp["result"]["content"]
      result = JSON.decode!(content["text"])
      assert is_binary(result["obs_sha"])
      assert byte_size(result["obs_sha"]) == 64
      refute Map.has_key?(result, "dec_sha")
      refute Map.has_key?(result, "act_sha")
    end

    test "observation + decision — returns obs_sha and dec_sha" do
      responses =
        run_session([
          init_line(),
          bias_call(2, %{
            annotation: "@work",
            observation: %{ref: "file:lib/app.ex", payload: "checked types"},
            decision: %{payload: "types are correct"}
          })
        ])

      resp = Enum.find(responses, &(&1["id"] == 2))
      [content] = resp["result"]["content"]
      result = JSON.decode!(content["text"])
      assert is_binary(result["obs_sha"])
      assert is_binary(result["dec_sha"])
      refute Map.has_key?(result, "act_sha")
    end

    test "full ODA — returns obs_sha, dec_sha, act_sha" do
      responses =
        run_session([
          init_line(),
          bias_call(2, %{
            annotation: "@work",
            observation: %{ref: "file:lib/app.ex", payload: "checked types"},
            decision: %{payload: "needs refactor"},
            action: %{payload: "refactored module"}
          })
        ])

      resp = Enum.find(responses, &(&1["id"] == 2))
      [content] = resp["result"]["content"]
      result = JSON.decode!(content["text"])
      assert is_binary(result["obs_sha"])
      assert is_binary(result["dec_sha"])
      assert is_binary(result["act_sha"])
    end

    test "action without decision — error" do
      responses =
        run_session([
          init_line(),
          bias_call(2, %{
            annotation: "@work",
            observation: %{ref: "file:x", payload: "data"},
            action: %{payload: "did thing"}
          })
        ])

      resp = Enum.find(responses, &(&1["id"] == 2))
      [content] = resp["result"]["content"]
      assert resp["result"]["isError"] == true
      assert String.contains?(content["text"], "decision")
    end

    test "deterministic — same inputs produce same SHAs" do
      args = %{
        annotation: "@work",
        observation: %{ref: "file:lib/app.ex", payload: "checked"}
      }

      responses_a = run_session([init_line(), bias_call(2, args)])
      responses_b = run_session([init_line(), bias_call(2, args)])

      resp_a = Enum.find(responses_a, &(&1["id"] == 2))
      resp_b = Enum.find(responses_b, &(&1["id"] == 2))

      result_a = JSON.decode!(hd(resp_a["result"]["content"])["text"])
      result_b = JSON.decode!(hd(resp_b["result"]["content"])["text"])

      assert result_a["obs_sha"] == result_b["obs_sha"]
    end
  end

  describe "commit tool" do
    test "seals session and returns root_sha" do
      responses =
        run_session([
          init_line(),
          bias_call(2, %{
            annotation: "@work",
            observation: %{ref: "file:x", payload: "data"}
          }),
          commit_call(3, %{annotation: "@commit"})
        ])

      resp = Enum.find(responses, &(&1["id"] == 3))
      assert resp["result"]["isError"] == false
      [content] = resp["result"]["content"]
      result = JSON.decode!(content["text"])
      assert is_binary(result["root_sha"])
      assert byte_size(result["root_sha"]) == 64
    end

    test "empty session commit still works" do
      responses =
        run_session([
          init_line(),
          commit_call(2, %{annotation: "@commit"})
        ])

      resp = Enum.find(responses, &(&1["id"] == 2))
      assert resp["result"]["isError"] == false
      [content] = resp["result"]["content"]
      result = JSON.decode!(content["text"])
      assert is_binary(result["root_sha"])
    end
  end

  describe "round-trip" do
    setup do
      start_supervised!({Witness.Store.Mnesia, context: Witness.Server, storage_type: :ram_copies})

      :mnesia.clear_table(Module.concat(Witness.Server, WitnessEvents))

      # Wire telemetry → Mnesia so Session events become queryable
      events = [
        [:witness, :session, :act],
        [:witness, :session, :decide],
        [:witness, :session, :observe],
        [:witness, :session, :commit]
      ]

      handler_id = "test-mcp-round-trip-#{inspect(make_ref())}"

      :telemetry.attach_many(
        handler_id,
        events,
        fn event, measurements, metadata, _config ->
          Witness.Store.Mnesia.store_event(event, metadata, measurements, Witness.Server, [])
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)
      :ok
    end

    test "bias emits telemetry visible to list_events" do
      responses =
        run_session([
          init_line(),
          bias_call(2, %{
            annotation: "@work",
            observation: %{ref: "file:x", payload: "data"},
            decision: %{payload: "ok"},
            action: %{payload: "done"}
          }),
          ~s({"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list_events","arguments":{}}})
        ])

      events_resp = Enum.find(responses, &(&1["id"] == 3))
      [content] = events_resp["result"]["content"]
      text = content["text"]

      # Telemetry events from Session.act, Session.decide, Session.observe
      assert String.contains?(text, "witness.session.act")
      assert String.contains?(text, "witness.session.decide")
      assert String.contains?(text, "witness.session.observe")
    end
  end
end
