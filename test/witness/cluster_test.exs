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

  describe "satellite_node_name/4" do
    test "embeds app, pwd, uuid, and hostname" do
      name = Witness.Cluster.satellite_node_name(:glue, "/Users/alex/dev/projects/glue", "abc123", "myhost")
      assert name == :"glue-/Users/alex/dev/projects/glue-abc123@myhost"
    end

    test "different pwd and uuid produce different names" do
      a = Witness.Cluster.satellite_node_name(:glue, "/path/a", "uuid1", "host")
      b = Witness.Cluster.satellite_node_name(:glue, "/path/b", "uuid2", "host")
      refute a == b
    end
  end
end
