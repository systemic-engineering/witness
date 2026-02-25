defmodule WitnessTest do
  use ExUnit.Case, async: true

  import Witness

  doctest Witness

  defmodule TestContext do
    use Witness,
      app: :witness,
      prefix: [:test]
  end

  defmodule ContextWithSources do
    use Witness,
      app: :witness,
      prefix: [:with_sources],
      sources: [TestModule1, TestModule2]
  end

  describe "context?/1" do
    test "returns true for valid context modules" do
      assert Witness.context?(TestContext)
    end

    test "returns false for non-context modules" do
      refute Witness.context?(Enum)
    end

    test "returns false for nil" do
      refute Witness.context?(nil)
    end

    test "returns false for non-modules" do
      refute Witness.context?("string")
      refute Witness.context?(["list"])
    end

    test "returns false for atom that's not a module" do
      refute Witness.context?(:some_atom)
    end
  end

  describe "config/1" do
    test "returns config for a context" do
      config = Witness.config(TestContext)

      assert is_list(config)
      assert config[:app] == :witness
      assert config[:prefix] == [:test]
    end
  end

  describe "config/2" do
    test "returns specific config value" do
      assert Witness.config(TestContext, :app) == :witness
      assert Witness.config(TestContext, :prefix) == [:test]
      assert Witness.config(TestContext, :active) == true
    end
  end

  describe "defaults/1" do
    test "returns defaults without app" do
      defaults = Witness.defaults()

      assert defaults[:active] == true
      assert defaults[:extra_events] == []
      assert defaults[:handler] == [Witness.Handler.OpenTelemetry]
    end

    test "returns defaults with app" do
      defaults = Witness.defaults(:witness)

      assert defaults[:app] == :witness
      assert defaults[:active] == true
    end

    test "merges application config when present" do
      # Set some test config
      Application.put_env(:test_app, Witness, handler: [SomeTestHandler])

      defaults = Witness.defaults(:test_app)

      assert defaults[:app] == :test_app
      assert defaults[:handler] == [SomeTestHandler]

      # Cleanup
      Application.delete_env(:test_app, Witness)
    end
  end

  describe "sources_in/1" do
    test "returns explicitly configured sources" do
      {:ok, sources} = Witness.sources_in(ContextWithSources)

      assert sources == [TestModule1, TestModule2]
    end

    test "resolves sources from application when not configured" do
      {:ok, sources} = Witness.sources_in(TestContext)

      # Should find sources from the witness app
      assert is_list(sources)
    end

    test "returns error for unknown app" do
      defmodule UnknownAppContext do
        use Witness,
          app: :totally_unknown_app,
          prefix: [:unknown]
      end

      assert {:error, {:unknown_app, :totally_unknown_app}} =
               Witness.sources_in(UnknownAppContext)
    end
  end

  describe "__using__ macro" do
    test "raises when config is not a keyword list" do
      assert_raise ArgumentError, ~r/expected config to be a keyword list/, fn ->
        defmodule InvalidConfig do
          use Witness, "not a keyword list"
        end
      end
    end

    test "generates config/0 that merges app config when app is present" do
      config = TestContext.config()

      assert config[:app] == :witness
      assert config[:prefix] == [:test]
    end
  end

  describe "child_spec/1" do
    test "generates valid child_spec" do
      spec = TestContext.child_spec(:ignored)

      assert spec.id == {Witness.Supervisor, TestContext}
      assert spec.type == :supervisor
    end
  end

  describe "source?/1" do
    test "delegates to Witness.Source" do
      # This is tested in source_test.exs, just verify delegation works
      refute Witness.source?(NotASource)
    end
  end

  describe "store config" do
    test "accepts a valid :store config with {module, config} tuple" do
      defmodule ContextWithStore do
        use Witness,
          app: :witness,
          prefix: [:test, :store],
          store: {Witness.Store.Mnesia, []}
      end

      config = ContextWithStore.config()
      assert config[:store] == {Witness.Store.Mnesia, []}
    end

    test "accepts nil :store config" do
      defmodule ContextWithNilStore do
        use Witness,
          app: :witness,
          prefix: [:test, :nil_store],
          store: nil
      end

      config = ContextWithNilStore.config()
      assert config[:store] == nil
    end

    test "store defaults to nil when not configured" do
      config = TestContext.config()
      assert config[:store] == nil
    end
  end
end
