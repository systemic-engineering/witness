defmodule WitnessTest do
  use ExUnit.Case, async: true

  require Witness

  describe "is_context/1 guard" do
    test "allows modules in guards" do
      assert check_context(SomeModule)
    end

    test "rejects nil in guards" do
      refute check_context(nil)
    end

    test "rejects non-atoms in guards" do
      refute check_context("string")
      refute check_context(123)
    end

    defp check_context(value) when Witness.is_context(value), do: true
    defp check_context(_), do: false
  end

  describe "defaults/1" do
    test "returns default config" do
      defaults = Witness.defaults(:test_app)
      assert defaults[:app] == :test_app
      assert defaults[:active] == true
      assert is_list(defaults[:handler])
    end
  end
end
