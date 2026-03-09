defmodule Witness.RegistryTest do
  use ExUnit.Case, async: false

  setup do
    # Start the registry for each test
    start_supervised!(Witness.Registry)
    :ok
  end

  describe "register and lookup" do
    test "registers a module to the current process" do
      assert :ok = Witness.Registry.register(MyApp.Context)
      assert {:ok, self()} == Witness.Registry.lookup(MyApp.Context)
    end

    test "lookup returns :error for unregistered module" do
      assert :error == Witness.Registry.lookup(UnknownModule)
    end

    test "unregisters a module" do
      :ok = Witness.Registry.register(MyApp.ToUnregister)
      assert {:ok, _} = Witness.Registry.lookup(MyApp.ToUnregister)

      :ok = Witness.Registry.unregister(MyApp.ToUnregister)
      assert :error == Witness.Registry.lookup(MyApp.ToUnregister)
    end
  end
end
