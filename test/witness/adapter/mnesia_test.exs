defmodule Witness.Adapter.MnesiaTest do
  use ExUnit.Case, async: false

  alias Witness.Event

  # Define a test repo using the Mnesia adapter
  defmodule TestRepo do
    use Ecto.Repo,
      otp_app: :witness,
      adapter: Witness.Adapter.Mnesia
  end

  setup do
    :mnesia.start()
    start_supervised!(TestRepo)
    :ok
  end

  describe "insert" do
    test "content-addresses data via :bias.hash and returns SHA" do
      commit = %Event{data: "hello world", message: "test", parent: nil}
      assert {:ok, inserted} = TestRepo.insert(commit)
      assert is_binary(inserted.sha)
      assert byte_size(inserted.sha) == 64
    end

    test "same data produces same SHA (deterministic)" do
      commit1 = %Event{data: "deterministic", message: "a", parent: nil}
      commit2 = %Event{data: "deterministic", message: "b", parent: nil}

      {:ok, c1} = TestRepo.insert(commit1)
      {:ok, c2} = TestRepo.insert(commit2)
      assert c1.sha == c2.sha
    end

    test "different data produces different SHA" do
      {:ok, c1} = TestRepo.insert(%Event{data: "alpha", message: "x", parent: nil})
      {:ok, c2} = TestRepo.insert(%Event{data: "beta", message: "x", parent: nil})
      refute c1.sha == c2.sha
    end

    test "preserves message and parent fields" do
      {:ok, inserted} = TestRepo.insert(%Event{data: "d", message: "my annotation", parent: "abc123"})
      assert inserted.message == "my annotation"
      assert inserted.parent == "abc123"
    end
  end

  describe "get" do
    test "retrieves commit by SHA" do
      {:ok, inserted} = TestRepo.insert(%Event{data: "retrievable", message: "msg", parent: nil})
      found = TestRepo.get(Event, inserted.sha)
      assert found.sha == inserted.sha
      assert found.data == "retrievable"
      assert found.message == "msg"
      assert found.parent == nil
    end

    test "returns nil for unknown SHA" do
      assert TestRepo.get(Event, "nonexistent") == nil
    end
  end

  describe "immutability" do
    test "update raises" do
      {:ok, inserted} = TestRepo.insert(%Event{data: "immutable", message: "x", parent: nil})
      changeset = Ecto.Changeset.change(inserted, data: "changed")
      assert_raise RuntimeError, ~r/immutable/, fn -> TestRepo.update(changeset) end
    end

    test "delete raises" do
      {:ok, inserted} = TestRepo.insert(%Event{data: "permanent", message: "x", parent: nil})
      assert_raise RuntimeError, ~r/delete/, fn -> TestRepo.delete(inserted) end
    end
  end
end
