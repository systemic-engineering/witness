defmodule Witness.Session.ServerTest do
  use ExUnit.Case, async: true

  alias Witness.Session
  alias Witness.Session.Ref

  describe "start_link/1" do
    test "starts a session process" do
      {:ok, pid} = Session.start_link(name: "test", author: "reed@systemic.engineer")
      assert Process.alive?(pid)
    end

    test "accepts repos option" do
      {:ok, pid} =
        Session.start_link(
          name: "test",
          author: "reed@systemic.engineer",
          repos: [Witness.InMemory]
        )

      assert Process.alive?(pid)
    end
  end

  describe "join/2 and participants/1" do
    test "caller joins as participant" do
      {:ok, pid} = Session.start_link(name: "test", author: "reed@systemic.engineer")
      :ok = Session.join(pid)
      assert self() in Session.participants(pid)
    end

    test "join with identity" do
      {:ok, pid} = Session.start_link(name: "test", author: "reed@systemic.engineer")
      identity = %Witness.Actor.Identity{name: "reed", email: "reed@systemic.engineer"}
      :ok = Session.join(pid, identity)
      assert self() in Session.participants(pid)
    end

    test "join is idempotent" do
      {:ok, pid} = Session.start_link(name: "test", author: "reed@systemic.engineer")
      :ok = Session.join(pid)
      :ok = Session.join(pid)
      # Only appears once
      assert length(Session.participants(pid)) == 1
    end
  end

  describe "leave/1" do
    test "removes caller from participants" do
      {:ok, pid} = Session.start_link(name: "test", author: "reed@systemic.engineer")
      :ok = Session.join(pid)
      assert self() in Session.participants(pid)
      :ok = Session.leave(pid)
      refute self() in Session.participants(pid)
    end
  end

  describe "participant DOWN" do
    test "removes participant when process dies" do
      {:ok, pid} = Session.start_link(name: "test", author: "reed@systemic.engineer")

      # Join from self so session doesn't immediately grace
      :ok = Session.join(pid)

      # Spawn a participant that joins then dies
      task =
        Task.async(fn ->
          Session.join(pid)
          :joined
        end)

      Task.await(task)
      # Give the DOWN message time to arrive
      Process.sleep(50)

      participants = Session.participants(pid)
      assert self() in participants
      assert length(participants) == 1
    end

    test "last participant DOWN starts grace timer" do
      {:ok, pid} =
        Session.start_link(
          name: "test",
          author: "reed@systemic.engineer",
          grace_ms: 100
        )

      task =
        Task.async(fn ->
          Session.join(pid)
          :joined
        end)

      Task.await(task)
      # Grace timer should fire, session should stop
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500
    end

    test "join during grace cancels timer" do
      {:ok, pid} =
        Session.start_link(
          name: "test",
          author: "reed@systemic.engineer",
          grace_ms: 200
        )

      task =
        Task.async(fn ->
          Session.join(pid)
          :joined
        end)

      Task.await(task)

      # Join quickly before grace expires
      Process.sleep(50)
      :ok = Session.join(pid)

      # Wait past the original grace period
      Process.sleep(300)
      assert Process.alive?(pid)
    end
  end

  describe "bias/5" do
    setup do
      {:ok, pid} = Session.start_link(name: "test", author: "reed@systemic.engineer")
      :ok = Session.join(pid)
      %{pid: pid}
    end

    test "produces obs_sha", %{pid: pid} do
      obs = %{"ref" => "file:test.ex", "payload" => "observed"}
      {:ok, result} = Session.bias(pid, "@signal", obs, nil, nil)
      assert is_binary(result.obs_sha)
      assert byte_size(result.obs_sha) == 64
    end

    test "full ODA cascade with decision and action", %{pid: pid} do
      obs = %{"ref" => "file:test.ex", "payload" => "observed"}
      dec = %{"payload" => "decided"}
      act = %{"payload" => "acted"}
      {:ok, result} = Session.bias(pid, "@signal", obs, dec, act)
      assert is_binary(result.obs_sha)
      assert is_binary(result.dec_sha)
      assert is_binary(result.act_sha)
    end

    test "action without decision returns error", %{pid: pid} do
      obs = %{"ref" => "file:test.ex", "payload" => "observed"}
      act = %{"payload" => "acted"}
      {:error, reason} = Session.bias(pid, "@signal", obs, nil, act)
      assert reason == "Action requires a decision"
    end

    test "advances head", %{pid: pid} do
      assert Session.head(pid) == nil
      obs = %{"ref" => "file:test.ex", "payload" => "observed"}
      {:ok, _result} = Session.bias(pid, "@signal", obs, nil, nil)
      assert is_binary(Session.head(pid))
    end
  end

  describe "seal/2" do
    setup do
      {:ok, pid} = Session.start_link(name: "test", author: "reed@systemic.engineer")
      :ok = Session.join(pid)
      %{pid: pid}
    end

    test "returns root SHA", %{pid: pid} do
      obs = %{"ref" => "init", "payload" => "data"}
      {:ok, _} = Session.bias(pid, "@init", obs, nil, nil)
      {:ok, root_sha} = Session.seal(pid, "@exit")
      assert is_binary(root_sha)
      assert byte_size(root_sha) == 64
    end

    test "resets ODA state after seal", %{pid: pid} do
      obs = %{"ref" => "init", "payload" => "data"}
      {:ok, _} = Session.bias(pid, "@init", obs, nil, nil)
      {:ok, _root_sha} = Session.seal(pid, "@exit")

      # New bias should work — fresh state
      obs2 = %{"ref" => "second", "payload" => "data2"}
      {:ok, result} = Session.bias(pid, "@signal", obs2, nil, nil)
      assert is_binary(result.obs_sha)
    end
  end

  describe "query/2" do
    setup do
      :mnesia.start()
      start_supervised!(Witness.InMemory)

      {:ok, pid} =
        Session.start_link(
          name: "test",
          author: "reed@systemic.engineer",
          repos: [Witness.InMemory]
        )

      :ok = Session.join(pid)
      %{pid: pid}
    end

    test "returns event by SHA", %{pid: pid} do
      obs = %{"ref" => "file:test.ex", "payload" => "observed"}
      {:ok, result} = Session.bias(pid, "@signal", obs, nil, nil)
      {:ok, event} = Session.query(pid, result.obs_sha)
      assert event.sha == result.obs_sha
    end

    test "returns head event", %{pid: pid} do
      obs = %{"ref" => "file:test.ex", "payload" => "observed"}
      {:ok, _result} = Session.bias(pid, "@signal", obs, nil, nil)
      {:ok, event} = Session.query(pid, :head)
      assert is_binary(event.sha)
    end

    test "returns error for unknown SHA", %{pid: pid} do
      {:error, _reason} = Session.query(pid, "0000000000000000000000000000000000000000000000000000000000000000")
    end

    test "returns error when no head", %{pid: pid} do
      {:error, _reason} = Session.query(pid, :head)
    end
  end

  describe "sealed session (grace expiry)" do
    test "auto-seals on grace expiry" do
      {:ok, pid} =
        Session.start_link(
          name: "test",
          author: "reed@systemic.engineer",
          grace_ms: 50
        )

      task =
        Task.async(fn ->
          Session.join(pid)
          obs = %{"ref" => "init", "payload" => "data"}
          Session.bias(pid, "@init", obs, nil, nil)
          :done
        end)

      Task.await(task)
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500
    end
  end
end
