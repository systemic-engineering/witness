defmodule Witness.ActorTest do
  use ExUnit.Case, async: false

  alias Witness.Actor
  alias Witness.Event

  defmodule TestRepo do
    use Witness.Repo
  end

  setup do
    :mnesia.start()
    start_supervised!(TestRepo)
    :ok
  end

  describe "new/1" do
    test "creates actor with identity and fresh session" do
      actor = Actor.new(name: "reed", email: "reed@systemic.engineer", repo: TestRepo)
      assert actor.name == "reed"
      assert actor.email == "reed@systemic.engineer"
      assert actor.repo == TestRepo
      assert actor.head == nil
    end
  end

  describe "identity/1" do
    test "returns name and email" do
      actor = Actor.new(name: "reed", email: "reed@systemic.engineer", repo: TestRepo)
      assert Actor.identity(actor) == %{name: "reed", email: "reed@systemic.engineer"}
    end
  end

  describe "bias/5" do
    test "observation-only returns obs_sha and persists commit" do
      actor = Actor.new(name: "reed", repo: TestRepo)
      obs = %{"ref" => "test/ref", "payload" => "what I saw"}

      {actor, result} = Actor.bias(actor, "@test", obs, nil, nil)

      assert is_binary(result.obs_sha)
      assert actor.head == result.obs_sha

      # Commit was persisted
      found = TestRepo.get(Event, result.obs_sha)
      assert found != nil
      assert found.message == "@test"
    end

    test "observation + decision returns both SHAs" do
      actor = Actor.new(name: "reed", repo: TestRepo)
      obs = %{"ref" => "test/ref", "payload" => "observed"}
      dec = %{"payload" => "decided this"}

      {_actor, result} = Actor.bias(actor, "@test", obs, dec, nil)

      assert is_binary(result.obs_sha)
      assert is_binary(result.dec_sha)
    end

    test "full cascade returns obs, dec, act SHAs" do
      actor = Actor.new(name: "reed", repo: TestRepo)
      obs = %{"ref" => "test/ref", "payload" => "observed"}
      dec = %{"payload" => "decided"}
      act = %{"payload" => "acted"}

      {_actor, result} = Actor.bias(actor, "@test", obs, dec, act)

      assert is_binary(result.obs_sha)
      assert is_binary(result.dec_sha)
      assert is_binary(result.act_sha)
    end

    test "action without decision returns error" do
      actor = Actor.new(name: "reed", repo: TestRepo)
      obs = %{"ref" => "test", "payload" => "data"}
      act = %{"payload" => "acted"}

      {_actor, result} = Actor.bias(actor, "@test", obs, nil, act)
      assert result == {:error, "Action requires a decision"}
    end

    test "sequential bias calls create parent chain" do
      actor = Actor.new(name: "reed", repo: TestRepo)

      {actor, r1} = Actor.bias(actor, "@first", %{"ref" => "a", "payload" => "1"}, nil, nil)
      {_actor, r2} = Actor.bias(actor, "@second", %{"ref" => "b", "payload" => "2"}, nil, nil)

      c1 = TestRepo.get(Event, r1.obs_sha)
      c2 = TestRepo.get(Event, r2.obs_sha)

      assert c1.parent == nil
      assert c2.parent == r1.obs_sha
    end
  end

  describe "seal/2" do
    test "creates closing commit and returns root_sha" do
      actor = Actor.new(name: "reed", repo: TestRepo)
      {actor, _} = Actor.bias(actor, "@obs", %{"ref" => "x", "payload" => "y"}, nil, nil)

      {_actor, root_sha} = Actor.seal(actor, "@exit")
      assert is_binary(root_sha)

      root = TestRepo.get(Event, root_sha)
      assert root != nil
      assert root.message == "@exit"
    end
  end
end
