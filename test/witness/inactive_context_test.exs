defmodule Witness.InactiveContextTest do
  use ExUnit.Case, async: true

  describe "inactive context (active: false)" do
    defmodule InactiveContext do
      use Witness,
        app: :witness,
        prefix: [:test, :inactive],
        active: false
    end

    defmodule SourceWithInactiveContext do
      require InactiveContext, as: O11y

      def tracked_function do
        O11y.with_span [:test, :function], %{foo: "bar"} do
          O11y.track_event([:test, :event], %{data: "value"})
          :result
        end
      end
    end

    test "with_span works when context is inactive (no ETS table)" do
      # Context is not supervised, ETS table doesn't exist
      # But code should still work (as noop)
      assert :result = SourceWithInactiveContext.tracked_function()
    end

    test "track_event works when context is inactive (no ETS table)" do
      # Should not crash even when ETS table doesn't exist
      require InactiveContext, as: O11y

      assert :ok = O11y.track_event([:test], %{data: "test"})
    end
  end
end
