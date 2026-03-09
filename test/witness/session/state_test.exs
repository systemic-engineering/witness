defmodule Witness.Session.StateTest do
  use ExUnit.Case, async: true

  alias Witness.Session
  alias Witness.Session.Ref
  alias Witness.Session.State

  setup do
    state = State.new(%{author: "reed@systemic.engineer", name: "test-session"})
    %{state: state}
  end

  describe "new/1" do
    test "creates session with config and returns %Session{}", %{state: state} do
      assert %Session{} = state
      assert State.head(state) == ""
      assert State.last_root(state) == nil
      config = State.config(state)
      assert config.author == "reed@systemic.engineer"
      assert config.name == "test-session"
    end
  end

  describe "act/3" do
    test "creates terminal entry and returns ActRef", %{state: state} do
      {updated, ref} = State.act(state, "@work", "state:uphill_late")
      assert Ref.kind(ref) == :act
      assert is_binary(Ref.sha(ref))
      assert byte_size(Ref.sha(ref)) == 64
      assert State.head(updated) == Ref.sha(ref)
    end

    test "deterministic — same inputs produce same SHA", %{state: state} do
      {_, ref_a} = State.act(state, "@work", "state:uphill_late")
      {_, ref_b} = State.act(state, "@work", "state:uphill_late")
      assert Ref.sha(ref_a) == Ref.sha(ref_b)
    end
  end

  describe "decide/5" do
    test "wraps acts and returns DecRef", %{state: state} do
      {state, act_ref} = State.act(state, "@work", "state:uphill_late")
      {updated, dec_ref} = State.decide(state, "@work", act_ref, "deploy", [Ref.sha(act_ref)])
      assert Ref.kind(dec_ref) == :dec
      assert State.head(updated) == Ref.sha(dec_ref)
    end
  end

  describe "observe/5" do
    test "wraps decisions and returns ObsRef", %{state: state} do
      {state, act_ref} = State.act(state, "@work", "data")
      {state, dec_ref} = State.decide(state, "@work", act_ref, "rule", [])

      {updated, obs_ref} =
        State.observe(state, "@work", "file:lib/app.ex", "checked", [Ref.sha(dec_ref)])

      assert Ref.kind(obs_ref) == :obs
      assert State.head(updated) == Ref.sha(obs_ref)
    end
  end

  describe "commit/3" do
    test "seals session and returns root entry + SHA", %{state: state} do
      {state, act_ref} = State.act(state, "@work", "data")
      {state, _dec_ref} = State.decide(state, "@work", act_ref, "rule", [])
      {state, obs_ref} = State.observe(state, "@work", "file:x", "data", [])

      {updated, root_entry, root_sha} = State.commit(state, "@commit", [Ref.sha(obs_ref)])

      assert is_binary(root_sha)
      assert byte_size(root_sha) == 64
      assert root_entry.kind == :root
      assert State.head(updated) == root_sha
      assert State.last_root(updated) == {root_entry, root_sha}
    end
  end

  describe "round-trip" do
    test "full ODA cascade: act -> decide -> observe -> commit", %{state: state} do
      {state, act_ref} = State.act(state, "@work", "state:uphill_late")
      assert Ref.kind(act_ref) == :act

      {state, dec_ref} =
        State.decide(state, "@work", act_ref, "deploy", [Ref.sha(act_ref)])

      assert Ref.kind(dec_ref) == :dec

      {state, obs_ref} =
        State.observe(state, "@work", "file:lib/app.ex", "checked", [Ref.sha(dec_ref)])

      assert Ref.kind(obs_ref) == :obs

      {_state, root, root_sha} = State.commit(state, "@commit", [Ref.sha(obs_ref)])
      assert root.kind == :root
      assert byte_size(root_sha) == 64
    end
  end
end
