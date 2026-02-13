defmodule WitnessTest do
  use ExUnit.Case
  doctest Witness

  test "greets the world" do
    assert Witness.hello() == :world
  end
end
