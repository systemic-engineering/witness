defmodule Witness.SessionTest do
  use ExUnit.Case, async: true

  alias Witness.Session
  alias Witness.Session.Ref

  setup do
    session = Session.new(%{author: "reed@systemic.engineer", name: "test-session"})
    %{session: session}
  end

  describe "new/1" do
    test "creates session with config", %{session: session} do
      assert Session.head(session) == ""
      assert Session.last_root(session) == nil
      config = Session.config(session)
      assert config.author == "reed@systemic.engineer"
      assert config.name == "test-session"
    end
  end

  describe "act/3" do
    test "creates terminal entry and returns ActRef", %{session: session} do
      {updated, ref} = Session.act(session, "@work", "state:uphill_late")
      assert Ref.kind(ref) == :act
      assert is_binary(Ref.sha(ref))
      assert byte_size(Ref.sha(ref)) == 64
      assert Session.head(updated) == Ref.sha(ref)
    end

    test "deterministic — same inputs produce same SHA", %{session: session} do
      {_, ref_a} = Session.act(session, "@work", "state:uphill_late")
      {_, ref_b} = Session.act(session, "@work", "state:uphill_late")
      assert Ref.sha(ref_a) == Ref.sha(ref_b)
    end

    test "different inputs produce different SHAs", %{session: session} do
      {_, ref_a} = Session.act(session, "@work", "state:uphill_late")
      {_, ref_b} = Session.act(session, "@work", "state:downhill")
      assert Ref.sha(ref_a) != Ref.sha(ref_b)
    end

    test "emits telemetry event", %{session: session} do
      ref = make_ref()

      :telemetry.attach(
        "test-act-#{inspect(ref)}",
        [:witness, :session, :act],
        fn event, measurements, metadata, _ ->
          send(self(), {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      {_updated, act_ref} = Session.act(session, "@work", "state:uphill_late")

      assert_receive {:telemetry, [:witness, :session, :act], _measurements, metadata}
      assert metadata.annotation == "@work"
      assert metadata.sha == Ref.sha(act_ref)

      :telemetry.detach("test-act-#{inspect(ref)}")
    end
  end

  describe "decide/5" do
    test "wraps acts and returns DecRef", %{session: session} do
      {session, act_ref} = Session.act(session, "@work", "state:uphill_late")
      {updated, dec_ref} = Session.decide(session, "@work", act_ref, "deploy", [Ref.sha(act_ref)])
      assert Ref.kind(dec_ref) == :dec
      assert Session.head(updated) == Ref.sha(dec_ref)
    end

    test "content includes obs_ref SHA for linkage", %{session: session} do
      {session, act_ref} = Session.act(session, "@work", "data1")
      {_, dec_ref_a} = Session.decide(session, "@work", act_ref, "rule-a", [])
      # Different obs_ref → different SHA
      other_ref = Ref.obs("different-observation")
      {_, dec_ref_b} = Session.decide(session, "@work", other_ref, "rule-a", [])
      assert Ref.sha(dec_ref_a) != Ref.sha(dec_ref_b)
    end

    test "emits telemetry event", %{session: session} do
      ref = make_ref()

      :telemetry.attach(
        "test-dec-#{inspect(ref)}",
        [:witness, :session, :decide],
        fn event, measurements, metadata, _ ->
          send(self(), {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      {session, act_ref} = Session.act(session, "@work", "data")
      {_updated, dec_ref} = Session.decide(session, "@work", act_ref, "deploy", [])

      assert_receive {:telemetry, [:witness, :session, :decide], _measurements, metadata}
      assert metadata.annotation == "@work"
      assert metadata.rule == "deploy"
      assert metadata.sha == Ref.sha(dec_ref)

      :telemetry.detach("test-dec-#{inspect(ref)}")
    end
  end

  describe "observe/5" do
    test "wraps decisions and returns ObsRef", %{session: session} do
      {session, act_ref} = Session.act(session, "@work", "data")
      {session, dec_ref} = Session.decide(session, "@work", act_ref, "rule", [])

      {updated, obs_ref} =
        Session.observe(session, "@work", "file:lib/app.ex", "checked", [Ref.sha(dec_ref)])

      assert Ref.kind(obs_ref) == :obs
      assert Session.head(updated) == Ref.sha(obs_ref)
    end

    test "emits telemetry event", %{session: session} do
      ref = make_ref()

      :telemetry.attach(
        "test-obs-#{inspect(ref)}",
        [:witness, :session, :observe],
        fn event, measurements, metadata, _ ->
          send(self(), {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      {session, act_ref} = Session.act(session, "@work", "data")
      {session, _dec_ref} = Session.decide(session, "@work", act_ref, "rule", [])

      {_updated, obs_ref} =
        Session.observe(session, "@work", "file:lib/app.ex", "observed data", [])

      assert_receive {:telemetry, [:witness, :session, :observe], _measurements, metadata}
      assert metadata.annotation == "@work"
      assert metadata.ref == "file:lib/app.ex"
      assert metadata.sha == Ref.sha(obs_ref)

      :telemetry.detach("test-obs-#{inspect(ref)}")
    end
  end

  describe "commit/3" do
    test "seals session and returns root entry + SHA", %{session: session} do
      {session, act_ref} = Session.act(session, "@work", "data")
      {session, _dec_ref} = Session.decide(session, "@work", act_ref, "rule", [])
      {session, obs_ref} = Session.observe(session, "@work", "file:x", "data", [])

      {updated, root_entry, root_sha} = Session.commit(session, "@commit", [Ref.sha(obs_ref)])

      assert is_binary(root_sha)
      assert byte_size(root_sha) == 64
      assert root_entry.kind == :root
      assert Session.head(updated) == root_sha
      assert Session.last_root(updated) == {root_entry, root_sha}
    end

    test "emits telemetry event", %{session: session} do
      ref = make_ref()

      :telemetry.attach(
        "test-commit-#{inspect(ref)}",
        [:witness, :session, :commit],
        fn event, measurements, metadata, _ ->
          send(self(), {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      {_updated, _root, root_sha} = Session.commit(session, "@commit", [])

      assert_receive {:telemetry, [:witness, :session, :commit], _measurements, metadata}
      assert metadata.annotation == "@commit"
      assert metadata.sha == root_sha
      assert metadata.name == "test-session"

      :telemetry.detach("test-commit-#{inspect(ref)}")
    end
  end

  describe "state threading" do
    test "head advances with each operation", %{session: session} do
      assert Session.head(session) == ""

      {session, act_ref} = Session.act(session, "@work", "d1")
      head1 = Session.head(session)
      assert head1 == Ref.sha(act_ref)

      {session, dec_ref} = Session.decide(session, "@work", act_ref, "rule", [])
      head2 = Session.head(session)
      assert head2 == Ref.sha(dec_ref)
      assert head2 != head1

      {session, obs_ref} = Session.observe(session, "@work", "file:x", "d", [])
      head3 = Session.head(session)
      assert head3 == Ref.sha(obs_ref)
      assert head3 != head2
    end
  end

  describe "round-trip" do
    test "full ODA cascade: act → decide → observe → commit", %{session: session} do
      # Act
      {session, act_ref} = Session.act(session, "@work", "state:uphill_late")
      assert Ref.kind(act_ref) == :act

      # Decide (links to act)
      {session, dec_ref} =
        Session.decide(session, "@work", act_ref, "deploy", [Ref.sha(act_ref)])

      assert Ref.kind(dec_ref) == :dec

      # Observe (wraps decisions)
      {session, obs_ref} =
        Session.observe(session, "@work", "file:lib/app.ex", "checked", [Ref.sha(dec_ref)])

      assert Ref.kind(obs_ref) == :obs

      # Commit (seals)
      {_session, root, root_sha} = Session.commit(session, "@commit", [Ref.sha(obs_ref)])
      assert root.kind == :root
      assert byte_size(root_sha) == 64
    end
  end
end
