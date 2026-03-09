defmodule Witness.Server.MCPBiasTest do
  use ExUnit.Case, async: false

  alias Witness.Server.MCP

  setup do
    :mnesia.start()
    start_supervised!(Witness.DefaultRepo)
    :ok
  end

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

  defp tool_call(id, name, args) do
    args_json = JSON.encode!(args)
    ~s({"jsonrpc":"2.0","id":#{id},"method":"tools/call","params":{"name":"#{name}","arguments":#{args_json}}})
  end

  describe "tools/list after init" do
    test "includes bias, query, exit tools with schemas" do
      responses =
        run_session([
          init_line(),
          tool_call(2, "init", %{name: "reed"}),
          ~s({"jsonrpc":"2.0","id":3,"method":"tools/list","params":{}})
        ])

      tool_list_resp = Enum.find(responses, &(&1["id"] == 3))
      names = Enum.map(tool_list_resp["result"]["tools"], & &1["name"])
      assert "bias" in names
      assert "query" in names
      assert "exit" in names
      refute "init" in names
    end

    test "bias tool has cascading input schema" do
      responses =
        run_session([
          init_line(),
          tool_call(2, "init", %{name: "reed"}),
          ~s({"jsonrpc":"2.0","id":3,"method":"tools/list","params":{}})
        ])

      tool_list_resp = Enum.find(responses, &(&1["id"] == 3))
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
          tool_call(2, "init", %{name: "reed"}),
          tool_call(3, "bias", %{
            annotation: "@work",
            observation: %{ref: "file:lib/app.ex", payload: "checked types"}
          })
        ])

      resp = Enum.find(responses, &(&1["id"] == 3))
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
          tool_call(2, "init", %{name: "reed"}),
          tool_call(3, "bias", %{
            annotation: "@work",
            observation: %{ref: "file:lib/app.ex", payload: "checked types"},
            decision: %{payload: "types are correct"}
          })
        ])

      resp = Enum.find(responses, &(&1["id"] == 3))
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
          tool_call(2, "init", %{name: "reed"}),
          tool_call(3, "bias", %{
            annotation: "@work",
            observation: %{ref: "file:lib/app.ex", payload: "checked types"},
            decision: %{payload: "needs refactor"},
            action: %{payload: "refactored module"}
          })
        ])

      resp = Enum.find(responses, &(&1["id"] == 3))
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
          tool_call(2, "init", %{name: "reed"}),
          tool_call(3, "bias", %{
            annotation: "@work",
            observation: %{ref: "file:x", payload: "data"},
            action: %{payload: "did thing"}
          })
        ])

      resp = Enum.find(responses, &(&1["id"] == 3))
      [content] = resp["result"]["content"]
      assert resp["result"]["isError"] == true
      assert String.contains?(content["text"], "decision")
    end

    test "deterministic — same inputs produce same SHAs" do
      args = %{
        annotation: "@work",
        observation: %{ref: "file:lib/app.ex", payload: "checked"}
      }

      responses_a =
        run_session([
          init_line(),
          tool_call(2, "init", %{name: "reed"}),
          tool_call(3, "bias", args)
        ])

      responses_b =
        run_session([
          init_line(),
          tool_call(2, "init", %{name: "reed"}),
          tool_call(3, "bias", args)
        ])

      resp_a = Enum.find(responses_a, &(&1["id"] == 3))
      resp_b = Enum.find(responses_b, &(&1["id"] == 3))

      result_a = JSON.decode!(hd(resp_a["result"]["content"])["text"])
      result_b = JSON.decode!(hd(resp_b["result"]["content"])["text"])

      assert result_a["obs_sha"] == result_b["obs_sha"]
    end
  end

  describe "exit tool" do
    test "seals session and returns root_sha" do
      responses =
        run_session([
          init_line(),
          tool_call(2, "init", %{name: "reed"}),
          tool_call(3, "bias", %{
            annotation: "@work",
            observation: %{ref: "file:x", payload: "data"}
          }),
          tool_call(4, "exit", %{annotation: "@done"})
        ])

      resp = Enum.find(responses, &(&1["id"] == 4))
      assert resp["result"]["isError"] == false
      [content] = resp["result"]["content"]
      result = JSON.decode!(content["text"])
      assert is_binary(result["root_sha"])
      assert byte_size(result["root_sha"]) == 64
    end
  end

  describe "round-trip query" do
    test "bias then query head returns the commit" do
      responses =
        run_session([
          init_line(),
          tool_call(2, "init", %{name: "reed"}),
          tool_call(3, "bias", %{
            annotation: "@work",
            observation: %{ref: "file:x", payload: "data"},
            decision: %{payload: "ok"},
            action: %{payload: "done"}
          }),
          tool_call(4, "query", %{head: true})
        ])

      # Get the obs_sha from bias
      bias_resp = Enum.find(responses, &(&1["id"] == 3))
      bias_result = JSON.decode!(hd(bias_resp["result"]["content"])["text"])

      # Query should return a commit
      query_resp = Enum.find(responses, &(&1["id"] == 4))
      assert query_resp["result"]["isError"] == false
      [content] = query_resp["result"]["content"]
      commit = JSON.decode!(content["text"])
      assert is_binary(commit["sha"])
      assert commit["sha"] == bias_result["obs_sha"]
    end
  end
end
