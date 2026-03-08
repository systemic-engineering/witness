defmodule Witness.ActionableTest do
  use ExUnit.Case, async: true

  alias Witness.Actionable

  describe "new/2" do
    test "creates actionable with target and empty config" do
      act = Actionable.new("alert")
      assert act.target == "alert"
      assert act.config == []
      assert is_binary(act.sha)
      assert byte_size(act.sha) == 64
    end

    test "creates actionable with target and config" do
      act = Actionable.new("notify", [{"channel", "#ops"}])
      assert act.target == "notify"
      assert act.config == [{"channel", "#ops"}]
    end

    test "deterministic — same inputs produce same SHA" do
      a = Actionable.new("alert", [{"level", "critical"}])
      b = Actionable.new("alert", [{"level", "critical"}])
      assert a.sha == b.sha
    end

    test "different inputs produce different SHAs" do
      a = Actionable.new("alert")
      b = Actionable.new("deploy")
      assert a.sha != b.sha
    end
  end
end
