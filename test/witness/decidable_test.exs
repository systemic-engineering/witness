defmodule Witness.DecidableTest do
  use ExUnit.Case, async: true

  alias Witness.Decidable

  describe "new/2" do
    test "creates decidable with variant and empty payload" do
      dec = Decidable.new("deploy")
      assert dec.variant == "deploy"
      assert dec.payload == []
      assert is_binary(dec.sha)
      assert byte_size(dec.sha) == 64
    end

    test "creates decidable with variant and payload" do
      dec = Decidable.new("escalate", [{"severity", "high"}])
      assert dec.variant == "escalate"
      assert dec.payload == [{"severity", "high"}]
    end

    test "deterministic — same inputs produce same SHA" do
      a = Decidable.new("deploy", [{"env", "prod"}])
      b = Decidable.new("deploy", [{"env", "prod"}])
      assert a.sha == b.sha
    end

    test "different inputs produce different SHAs" do
      a = Decidable.new("deploy")
      b = Decidable.new("rollback")
      assert a.sha != b.sha
    end
  end
end
