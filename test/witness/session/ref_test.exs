defmodule Witness.Session.RefTest do
  use ExUnit.Case, async: true

  alias Witness.Session.Ref

  describe "construction" do
    test "obs_ref wraps a SHA" do
      ref = Ref.obs("abc123")
      assert Ref.kind(ref) == :obs
      assert Ref.sha(ref) == "abc123"
    end

    test "dec_ref wraps a SHA" do
      ref = Ref.dec("def456")
      assert Ref.kind(ref) == :dec
      assert Ref.sha(ref) == "def456"
    end

    test "act_ref wraps a SHA" do
      ref = Ref.act("ghi789")
      assert Ref.kind(ref) == :act
      assert Ref.sha(ref) == "ghi789"
    end
  end

  describe "extraction" do
    test "sha/1 extracts SHA from any ref type" do
      assert Ref.sha(Ref.obs("a")) == "a"
      assert Ref.sha(Ref.dec("b")) == "b"
      assert Ref.sha(Ref.act("c")) == "c"
    end

    test "kind/1 extracts kind from any ref type" do
      assert Ref.kind(Ref.obs("a")) == :obs
      assert Ref.kind(Ref.dec("b")) == :dec
      assert Ref.kind(Ref.act("c")) == :act
    end
  end
end
