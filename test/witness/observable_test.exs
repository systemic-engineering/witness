defmodule Witness.ObservableTest do
  use ExUnit.Case, async: true

  alias Witness.Observable

  describe "new/2" do
    test "creates observable with kind and source" do
      obs = Observable.new("config", "postgres")
      assert obs.kind == "config"
      assert obs.source == "postgres"
      assert is_binary(obs.sha)
      assert byte_size(obs.sha) == 64
    end

    test "deterministic — same inputs produce same SHA" do
      a = Observable.new("config", "postgres")
      b = Observable.new("config", "postgres")
      assert a.sha == b.sha
    end

    test "different inputs produce different SHAs" do
      a = Observable.new("config", "postgres")
      b = Observable.new("config", "redis")
      assert a.sha != b.sha
    end
  end
end
