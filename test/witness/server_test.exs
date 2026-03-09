defmodule Witness.ServerTest do
  use ExUnit.Case, async: false

  describe "child_spec/0" do
    test "returns a valid supervisor child spec" do
      spec = Witness.Server.child_spec([])
      assert spec.id == Witness.Server
      assert spec.type == :supervisor
    end
  end

  describe "start_link/1" do
    test "starts InMemory as child" do
      :mnesia.start()
      {:ok, _pid} = start_supervised(Witness.Server)

      # Repo is running: can insert and read commits
      commit = %Witness.Event{sha: "test123", data: "hello", message: "@test", parent: nil}
      {:ok, _} = Witness.InMemory.insert(commit)

      found = Witness.InMemory.get(Witness.Event, "test123")
      assert found.data == "hello"
    end
  end
end
