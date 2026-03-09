defmodule Witness.RepoTest do
  use ExUnit.Case, async: false

  alias Witness.Event

  defmodule TestRepo do
    use Witness.Repo
  end

  setup do
    :mnesia.start()
    start_supervised!(TestRepo)
    :ok
  end

  describe "Witness.Repo macro" do
    test "insert and get roundtrip" do
      {:ok, inserted} = TestRepo.insert(%Event{data: "roundtrip", message: "test", parent: nil})
      assert is_binary(inserted.sha)

      found = TestRepo.get(Event, inserted.sha)
      assert found.data == "roundtrip"
      assert found.message == "test"
    end

    test "uses Mnesia adapter by default" do
      assert TestRepo.__adapter__() == Witness.Adapter.Mnesia
    end
  end
end
