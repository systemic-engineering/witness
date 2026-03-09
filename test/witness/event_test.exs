defmodule Witness.EventTest do
  use ExUnit.Case, async: true

  alias Witness.Event

  describe "schema" do
    test "has sha, data, message, parent fields" do
      fields = Event.__schema__(:fields)
      assert :sha in fields
      assert :data in fields
      assert :message in fields
      assert :parent in fields
    end

    test "sha is the primary key" do
      [pk] = Event.__schema__(:primary_key)
      assert pk == :sha
    end

    test "struct can be created with all fields" do
      event = %Event{sha: "abc123", data: "hello", message: "test", parent: nil}
      assert event.sha == "abc123"
      assert event.data == "hello"
      assert event.message == "test"
      assert event.parent == nil
    end
  end
end
