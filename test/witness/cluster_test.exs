defmodule Witness.ClusterTest do
  use ExUnit.Case, async: true

  describe "node_name/2" do
    test "builds a node atom from app name and hostname" do
      assert Witness.Cluster.node_name(:glue, "myhost") == :glue@myhost
    end

    test "works with any atom app name" do
      assert Witness.Cluster.node_name(:witness, "dev-machine") == :"witness@dev-machine"
    end
  end
end
