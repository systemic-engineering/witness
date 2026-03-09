defmodule Witness.Server.MCPTest do
  use ExUnit.Case, async: false

  alias Witness.Server.MCP

  setup do
    :mnesia.start()
    start_supervised!(Witness.DefaultRepo)
    :ok
  end

  defp run_request(json_line) do
    {:ok, io} = StringIO.open(json_line <> "\n")
    MCP.run(io)
    {_input, output} = StringIO.contents(io)
    output
  end

  defp decode_response(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.map(&JSON.decode!/1)
  end

  defp run_session(lines) do
    input = Enum.join(lines, "\n") <> "\n"
    {:ok, io} = StringIO.open(input)
    MCP.run(io)
    {_input, output} = StringIO.contents(io)
    output |> String.split("\n", trim: true) |> Enum.map(&JSON.decode!/1)
  end

  defp init_line do
    ~s({"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test-agent"}}})
  end

  defp tools_list(id) do
    ~s({"jsonrpc":"2.0","id":#{id},"method":"tools/list","params":{}})
  end

  defp tool_call(id, name, args) do
    args_json = JSON.encode!(args)
    ~s({"jsonrpc":"2.0","id":#{id},"method":"tools/call","params":{"name":"#{name}","arguments":#{args_json}}})
  end

  # ---------------------------------------------------------------------------
  # Protocol basics
  # ---------------------------------------------------------------------------

  describe "initialize" do
    test "responds with protocol version and server info" do
      [resp] = run_request(init_line()) |> decode_response()

      assert resp["id"] == 1
      assert resp["result"]["protocolVersion"] == "2024-11-05"
      assert resp["result"]["serverInfo"]["name"] == "witness-mcp"
    end
  end

  describe "unknown method" do
    test "returns method_not_found error" do
      req = ~s({"jsonrpc":"2.0","id":9,"method":"unknown/method","params":{}})
      [resp] = run_request(req) |> decode_response()
      assert resp["error"]["code"] == -32_601
    end
  end

  describe "parse error" do
    test "returns parse error on invalid JSON" do
      [resp] = run_request("not json") |> decode_response()
      assert resp["error"]["code"] == -32_700
    end
  end

  describe "ping" do
    test "responds with empty result" do
      req = ~s({"jsonrpc":"2.0","id":10,"method":"ping","params":{}})
      [resp] = run_request(req) |> decode_response()
      assert resp["result"] == %{}
    end
  end

  # ---------------------------------------------------------------------------
  # State machine — tool surface gating
  # ---------------------------------------------------------------------------

  describe "tools/list before init" do
    test "returns only init tool" do
      responses =
        run_session([
          init_line(),
          tools_list(2)
        ])

      tool_list = Enum.find(responses, &(&1["id"] == 2))
      names = Enum.map(tool_list["result"]["tools"], & &1["name"])
      assert names == ["init"]
    end
  end

  describe "init tool" do
    test "transitions to active and emits tools_changed notification" do
      responses =
        run_session([
          init_line(),
          tool_call(2, "init", %{name: "reed", email: "reed@systemic.engineer"}),
          tools_list(3)
        ])

      # Init response returns identity and init commit SHA
      init_resp = Enum.find(responses, &(&1["id"] == 2))
      assert init_resp["result"]["isError"] == false
      content = hd(init_resp["result"]["content"])
      result = JSON.decode!(content["text"])
      assert result["name"] == "reed"
      assert result["email"] == "reed@systemic.engineer"
      assert is_binary(result["obs_sha"])

      # tools/list_changed notification should be present
      notifications = Enum.filter(responses, &is_nil(&1["id"]))
      assert Enum.any?(notifications, &(&1["method"] == "notifications/tools/list_changed"))

      # After init, tools are bias, query, exit
      tool_list = Enum.find(responses, &(&1["id"] == 3))
      names = Enum.map(tool_list["result"]["tools"], & &1["name"])
      assert "bias" in names
      assert "query" in names
      assert "exit" in names
      refute "init" in names
    end

    test "init commit is queryable" do
      responses =
        run_session([
          init_line(),
          tool_call(2, "init", %{name: "reed"}),
          tool_call(3, "query", %{head: true})
        ])

      init_resp = Enum.find(responses, &(&1["id"] == 2))
      init_result = JSON.decode!(hd(init_resp["result"]["content"])["text"])

      query_resp = Enum.find(responses, &(&1["id"] == 3))
      assert query_resp["result"]["isError"] == false
      commit = JSON.decode!(hd(query_resp["result"]["content"])["text"])
      assert commit["sha"] == init_result["obs_sha"]
    end
  end

  describe "bias before init" do
    test "returns error" do
      responses =
        run_session([
          init_line(),
          tool_call(2, "bias", %{annotation: "@test", observation: %{ref: "x", payload: "y"}})
        ])

      resp = Enum.find(responses, &(&1["id"] == 2))
      assert resp["result"]["isError"] == true
    end
  end

  # ---------------------------------------------------------------------------
  # Active state — bias, query, exit
  # ---------------------------------------------------------------------------

  describe "bias after init" do
    test "observation-only returns obs_sha" do
      responses =
        run_session([
          init_line(),
          tool_call(2, "init", %{name: "reed"}),
          tool_call(3, "bias", %{annotation: "@test", observation: %{ref: "x", payload: "y"}})
        ])

      resp = Enum.find(responses, &(&1["id"] == 3))
      assert resp["result"]["isError"] == false
      content = hd(resp["result"]["content"])
      result = JSON.decode!(content["text"])
      assert is_binary(result["obs_sha"])
    end

    test "full cascade returns obs, dec, act SHAs" do
      responses =
        run_session([
          init_line(),
          tool_call(2, "init", %{name: "reed"}),
          tool_call(3, "bias", %{
            annotation: "@test",
            observation: %{ref: "x", payload: "y"},
            decision: %{payload: "decided"},
            action: %{payload: "acted"}
          })
        ])

      resp = Enum.find(responses, &(&1["id"] == 3))
      content = hd(resp["result"]["content"])
      result = JSON.decode!(content["text"])
      assert is_binary(result["obs_sha"])
      assert is_binary(result["dec_sha"])
      assert is_binary(result["act_sha"])
    end
  end

  describe "query after init" do
    test "retrieves commit by SHA" do
      responses =
        run_session([
          init_line(),
          tool_call(2, "init", %{name: "reed"}),
          tool_call(3, "bias", %{annotation: "@test", observation: %{ref: "x", payload: "y"}}),
          tool_call(4, "query", %{head: true})
        ])

      query_resp = Enum.find(responses, &(&1["id"] == 4))
      assert query_resp["result"]["isError"] == false
    end
  end

  describe "exit" do
    test "seals session and resets tools to init" do
      responses =
        run_session([
          init_line(),
          tool_call(2, "init", %{name: "reed"}),
          tool_call(3, "bias", %{annotation: "@test", observation: %{ref: "x", payload: "y"}}),
          tool_call(4, "exit", %{annotation: "@done"}),
          tools_list(5)
        ])

      # Exit returns root_sha
      exit_resp = Enum.find(responses, &(&1["id"] == 4))
      assert exit_resp["result"]["isError"] == false
      content = hd(exit_resp["result"]["content"])
      result = JSON.decode!(content["text"])
      assert is_binary(result["root_sha"])

      # tools/list_changed notification emitted again
      notifications = Enum.filter(responses, &is_nil(&1["id"]))
      tools_changed = Enum.filter(notifications, &(&1["method"] == "notifications/tools/list_changed"))
      assert length(tools_changed) >= 2

      # Tools reset to init
      tool_list = Enum.find(responses, &(&1["id"] == 5))
      names = Enum.map(tool_list["result"]["tools"], & &1["name"])
      assert names == ["init"]
    end
  end

  describe "notifications" do
    test "initialized notification gets no response" do
      lines = [
        ~s({"jsonrpc":"2.0","method":"notifications/initialized","params":{}}),
        ~s({"jsonrpc":"2.0","id":1,"method":"ping","params":{}})
      ]

      [resp] = run_session(lines)
      assert resp["id"] == 1
    end
  end
end
