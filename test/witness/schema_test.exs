defmodule Witness.SchemaTest do
  use ExUnit.Case, async: true

  describe "new schema options" do
    test "accepts parent option" do
      n = System.unique_integer([:positive])

      [{mod, _}] =
        Code.compile_string("""
        defmodule :"Elixir.Witness.SchemaTest.WithParent#{n}" do
          use Witness, app: :witness, prefix: [:schema, :parent], parent: SomeModule
        end
        """)

      assert mod.config()[:parent] == SomeModule
    end

    test "accepts repos option" do
      n = System.unique_integer([:positive])

      [{mod, _}] =
        Code.compile_string("""
        defmodule :"Elixir.Witness.SchemaTest.WithRepos#{n}" do
          use Witness, app: :witness, prefix: [:schema, :repos], repos: [Witness.InMemory]
        end
        """)

      assert mod.config()[:repos] == [Witness.InMemory]
    end

    test "accepts domain option" do
      n = System.unique_integer([:positive])

      [{mod, _}] =
        Code.compile_string("""
        defmodule :"Elixir.Witness.SchemaTest.WithDomain#{n}" do
          use Witness, app: :witness, prefix: [:schema, :domain], domain: :billing
        end
        """)

      assert mod.config()[:domain] == :billing
    end

    test "accepts supervise option" do
      n = System.unique_integer([:positive])

      [{mod, _}] =
        Code.compile_string("""
        defmodule :"Elixir.Witness.SchemaTest.WithSupervise#{n}" do
          use Witness, app: :witness, prefix: [:schema, :supervise], supervise: true
        end
        """)

      assert mod.config()[:supervise] == true
    end

    test "accepts snitch option" do
      n = System.unique_integer([:positive])

      [{mod, _}] =
        Code.compile_string("""
        defmodule :"Elixir.Witness.SchemaTest.WithSnitch#{n}" do
          use Witness, app: :witness, prefix: [:schema, :snitch], snitch: true
        end
        """)

      assert mod.config()[:snitch] == true
    end
  end

  describe "optional app and prefix" do
    test "app and prefix can be omitted when parent is set" do
      n = System.unique_integer([:positive])

      [{mod, _}] =
        Code.compile_string("""
        defmodule :"Elixir.Witness.SchemaTest.ChildOnly#{n}" do
          use Witness, parent: SomeRoot
        end
        """)

      config = mod.config()
      assert config[:parent] == SomeRoot
    end
  end
end
