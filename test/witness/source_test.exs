defmodule Witness.SourceTest do
  use ExUnit.Case, async: true

  alias Witness.Source

  defmodule ValidSource do
    @behaviour Source

    @impl true
    def __observable__ do
      %{
        context: MyContext,
        events: [[:event, :one], [:event, :two]]
      }
    end
  end

  defmodule NotASource do
    # Doesn't implement __observable__/0
  end

  describe "source?/1" do
    test "returns true for modules implementing the Source behaviour" do
      assert Source.source?(ValidSource)
    end

    test "returns false for modules not implementing the Source behaviour" do
      refute Source.source?(NotASource)
    end

    test "returns false for non-existent modules" do
      refute Source.source?(NonExistentModule)
    end
  end

  describe "info/1" do
    test "returns source info for valid sources" do
      info = Source.info(ValidSource)

      assert info == %{
               context: MyContext,
               events: [[:event, :one], [:event, :two]]
             }
    end

    test "returns nil for non-sources" do
      assert Source.info(NotASource) == nil
    end
  end

  describe "info/2" do
    test "returns context from source info" do
      assert Source.info(ValidSource, :context) == MyContext
    end

    test "returns events from source info" do
      assert Source.info(ValidSource, :events) == [[:event, :one], [:event, :two]]
    end

    test "returns nil for non-source module" do
      assert Source.info(NotASource, :context) == nil
    end
  end

  describe "info!/2" do
    test "returns value for valid source and key" do
      assert Source.info!(ValidSource, :context) == MyContext
      assert Source.info!(ValidSource, :events) == [[:event, :one], [:event, :two]]
    end

    test "raises ArgumentError for non-source module" do
      assert_raise ArgumentError,
                   ~r/the given module is not a source of observability events/,
                   fn ->
                     Source.info!(NotASource, :context)
                   end
    end
  end
end
