defmodule Witness.ModuleActorTest do
  use ExUnit.Case, async: false

  defmodule ActorRoot do
    use Witness,
      app: :witness,
      prefix: [:actor, :root],
      repos: [Witness.InMemory]
  end

  setup do
    start_supervised!(Witness.Registry)
    :ok
  end

  describe "Witness.start/1" do
    test "returns a %Witness{} with the module's compiled data" do
      witness = Witness.start(ActorRoot)

      assert %Witness{} = witness
      assert witness.module == ActorRoot
      assert witness.prefix == [:actor, :root]
    end

    test "sets t0 to a fresh monotonic time" do
      witness = Witness.start(ActorRoot)

      assert is_integer(witness.t0)
      assert witness.t0 != 0
    end
  end

  describe "Witness.ModuleActor" do
    test "starts and registers in the registry" do
      {:ok, pid} = Witness.ModuleActor.start_link(ActorRoot)

      assert {:ok, ^pid} = Witness.Registry.lookup(ActorRoot)
    end

    test "responds to :__witness__ call" do
      {:ok, pid} = Witness.ModuleActor.start_link(ActorRoot)

      witness = GenServer.call(pid, :__witness__)
      assert %Witness{} = witness
      assert witness.module == ActorRoot
    end
  end
end
