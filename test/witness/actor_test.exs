defmodule Witness.ActorTest do
  use ExUnit.Case, async: false

  alias Witness.Actor
  alias Witness.Event
  alias Witness.Session

  defmodule TestRepo do
    use Witness.Repo
  end

  defmodule ActorRoot do
    use Witness,
      app: :witness,
      prefix: [:actor, :root],
      repos: [Witness.InMemory]
  end

  setup do
    :mnesia.start()
    start_supervised!(TestRepo)
    start_supervised!(Witness.Registry)
    :ok
  end

  defp make_witness(opts \\ []) do
    name = Keyword.get(opts, :name, "reed")
    email = Keyword.get(opts, :email, "#{name}@witness")
    repo = Keyword.get(opts, :repo, TestRepo)

    identity = %Witness.Actor.Identity{
      name: name,
      email: email
    }

    %Witness{
      module: Witness.ActorTest,
      prefix: [:test],
      identity: identity,
      session: Session.new(%{author: email, name: name}),
      repos: [repo],
      head: nil
    }
  end

  describe "ODA: bias/5" do
    test "observation-only returns obs_sha and persists commit" do
      witness = make_witness()
      obs = %{"ref" => "test/ref", "payload" => "what I saw"}

      {witness, result} = Actor.bias(witness, "@test", obs, nil, nil)

      assert is_binary(result.obs_sha)
      assert witness.head == result.obs_sha

      # Commit was persisted
      found = TestRepo.get(Event, result.obs_sha)
      assert found != nil
      assert found.message == "@test"
    end

    test "observation + decision returns both SHAs" do
      witness = make_witness()
      obs = %{"ref" => "test/ref", "payload" => "observed"}
      dec = %{"payload" => "decided this"}

      {_witness, result} = Actor.bias(witness, "@test", obs, dec, nil)

      assert is_binary(result.obs_sha)
      assert is_binary(result.dec_sha)
    end

    test "full cascade returns obs, dec, act SHAs" do
      witness = make_witness()
      obs = %{"ref" => "test/ref", "payload" => "observed"}
      dec = %{"payload" => "decided"}
      act = %{"payload" => "acted"}

      {_witness, result} = Actor.bias(witness, "@test", obs, dec, act)

      assert is_binary(result.obs_sha)
      assert is_binary(result.dec_sha)
      assert is_binary(result.act_sha)
    end

    test "action without decision returns error" do
      witness = make_witness()
      obs = %{"ref" => "test", "payload" => "data"}
      act = %{"payload" => "acted"}

      {_witness, result} = Actor.bias(witness, "@test", obs, nil, act)
      assert result == {:error, "Action requires a decision"}
    end

    test "sequential bias calls create parent chain" do
      witness = make_witness()

      {witness, r1} = Actor.bias(witness, "@first", %{"ref" => "a", "payload" => "1"}, nil, nil)
      {_witness, r2} = Actor.bias(witness, "@second", %{"ref" => "b", "payload" => "2"}, nil, nil)

      c1 = TestRepo.get(Event, r1.obs_sha)
      c2 = TestRepo.get(Event, r2.obs_sha)

      assert c1.parent == nil
      assert c2.parent == r1.obs_sha
    end
  end

  describe "ODA: seal/2" do
    test "creates closing commit and returns root_sha" do
      witness = make_witness()
      {witness, _} = Actor.bias(witness, "@obs", %{"ref" => "x", "payload" => "y"}, nil, nil)

      {_witness, root_sha} = Actor.seal(witness, "@exit")
      assert is_binary(root_sha)

      root = TestRepo.get(Event, root_sha)
      assert root != nil
      assert root.message == "@exit"
    end
  end

  describe "GenServer" do
    test "starts and registers in the registry" do
      {:ok, pid} = Actor.start_link(ActorRoot)

      assert {:ok, ^pid} = Witness.Registry.lookup(ActorRoot)
    end

    test "responds to :__witness__ call" do
      {:ok, pid} = Actor.start_link(ActorRoot)

      witness = GenServer.call(pid, :__witness__)
      assert %Witness{} = witness
      assert witness.module == ActorRoot
    end
  end
end
