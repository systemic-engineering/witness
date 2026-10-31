defmodule Witness.Handler.RepoTest do
  use ExUnit.Case, async: false

  alias Witness.Handler.Repo, as: RepoHandler

  defmodule TestContext do
    use Witness,
      app: :witness,
      prefix: [:handler, :repo, :test]
  end

  defmodule TestRepo do
    use Witness.Repo
  end

  setup do
    :mnesia.start()
    start_supervised!(TestRepo)
    :ok
  end

  describe "handle_event/4" do
    test "persists a telemetry event as a Witness.Event via repo.insert" do
      RepoHandler.handle_event(
        [:user, :created],
        %{user_id: 42},
        %{source: "test"},
        {TestRepo, TestContext}
      )

      # Scan the Mnesia table for persisted records
      {:atomic, records} =
        :mnesia.transaction(fn -> :mnesia.match_object({:witness, :_, :_, :_, :_}) end)

      assert length(records) >= 1

      # Find the record with our namespace message
      {_, sha, data, message, _parent} =
        Enum.find(records, fn {_, _, _, msg, _} ->
          msg == "handler/repo/test/user/created"
        end)

      assert is_binary(sha)
      assert message == "handler/repo/test/user/created"

      decoded = JSON.decode!(data)
      assert decoded["event_name"] == ["user", "created"]
      assert decoded["attributes"]["user_id"] == 42
      assert decoded["meta"]["source"] == "test"
    end

    test "terms JSON can't hold are kept as text, with a note, never dropped" do
      pid = self()

      RepoHandler.handle_event(
        [:odd, :meta],
        %{n: 1},
        %{caller: {Some.Module, {:fun, 3}}, pid: pid, ref: make_ref(), fun: fn -> :ok end, plain: "text"},
        {TestRepo, TestContext}
      )

      {:atomic, records} =
        :mnesia.transaction(fn -> :mnesia.match_object({:witness, :_, :_, :_, :_}) end)

      {_, _, data, _, _} =
        Enum.find(records, fn {_, _, _, msg, _} -> msg == "handler/repo/test/odd/meta" end)

      decoded = JSON.decode!(data)
      assert decoded["meta"]["caller"] == inspect({Some.Module, {:fun, 3}})
      assert decoded["meta"]["pid"] == inspect(pid)
      assert decoded["meta"]["plain"] == "text"
      assert is_binary(decoded["meta"]["ref"])
      assert is_binary(decoded["meta"]["fun"])

      notes = decoded["notes"]
      assert Enum.sort(notes) == Enum.sort(["meta.caller", "meta.fun", "meta.pid", "meta.ref"])
    end

    test "message carries the witness namespace path" do
      RepoHandler.handle_event(
        [:actor, :witnessed],
        %{document: "abc"},
        %{},
        {TestRepo, TestContext}
      )

      {:atomic, records} =
        :mnesia.transaction(fn -> :mnesia.match_object({:witness, :_, :_, :_, :_}) end)

      messages = Enum.map(records, fn {_, _, _, msg, _} -> msg end)
      assert "handler/repo/test/actor/witnessed" in messages
    end

    test "stores multiple events with unique SHAs" do
      RepoHandler.handle_event([:event, :one], %{n: 1}, %{}, {TestRepo, TestContext})
      Process.sleep(1)
      RepoHandler.handle_event([:event, :two], %{n: 2}, %{}, {TestRepo, TestContext})

      {:atomic, records} =
        :mnesia.transaction(fn -> :mnesia.match_object({:witness, :_, :_, :_, :_}) end)

      messages = Enum.map(records, fn {_, _, _, msg, _} -> msg end)
      assert "handler/repo/test/event/one" in messages
      assert "handler/repo/test/event/two" in messages

      shas = Enum.map(records, fn {_, sha, _, _, _} -> sha end)
      assert length(Enum.uniq(shas)) == length(shas)
    end
  end

  describe "behaviour" do
    test "implements Witness.Handler behaviour" do
      assert Code.ensure_loaded?(RepoHandler)
      assert {:handle_event, 4} in RepoHandler.__info__(:functions)
    end

    test "does not implement child_spec/1 (repo is supervised elsewhere)" do
      refute {:child_spec, 1} in RepoHandler.__info__(:functions)
    end
  end
end
