defmodule Witness.StoreTest do
  use ExUnit.Case, async: true

  describe "behaviour" do
    test "Witness.Store module is defined" do
      assert Code.ensure_loaded?(Witness.Store)
    end

    test "defines store_event/5 callback" do
      callbacks = Witness.Store.behaviour_info(:callbacks)
      assert {:store_event, 5} in callbacks
    end

    test "defines list_events/3 callback" do
      callbacks = Witness.Store.behaviour_info(:callbacks)
      assert {:list_events, 3} in callbacks
    end

    test "defines child_spec/1 callback" do
      callbacks = Witness.Store.behaviour_info(:callbacks)
      assert {:child_spec, 1} in callbacks
    end
  end
end
