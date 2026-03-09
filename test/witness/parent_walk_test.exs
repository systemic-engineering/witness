defmodule Witness.ParentWalkTest do
  use ExUnit.Case, async: true

  # Root module — has app and prefix explicitly
  defmodule Root do
    use Witness,
      app: :witness,
      prefix: [:root],
      repos: [Witness.InMemory],
      domain: :billing
  end

  # Child module — inherits from Root
  defmodule Root.Child do
    use Witness
  end

  # Grandchild module — inherits transitively
  defmodule Root.Child.Grandchild do
    use Witness
  end

  # Module with explicit parent override
  defmodule Sibling do
    use Witness, parent: Root, prefix: [:sibling]
  end

  describe "parent-walk" do
    test "root has no parent" do
      compiled = Root.__witness_compiled__()
      assert compiled.parent == nil
    end

    test "child discovers root as parent" do
      compiled = Root.Child.__witness_compiled__()
      assert compiled.parent == Root
    end

    test "child inherits repos from parent" do
      compiled = Root.Child.__witness_compiled__()
      assert compiled.repos == [Witness.InMemory]
    end

    test "child inherits domain from parent" do
      compiled = Root.Child.__witness_compiled__()
      assert compiled.domain == :billing
    end

    test "child computes prefix from parent prefix + relative name" do
      compiled = Root.Child.__witness_compiled__()
      assert compiled.prefix == [:root, :child]
    end

    test "grandchild inherits transitively through parent chain" do
      compiled = Root.Child.Grandchild.__witness_compiled__()
      assert compiled.parent == Root.Child
      assert compiled.prefix == [:root, :child, :grandchild]
      assert compiled.repos == [Witness.InMemory]
      assert compiled.domain == :billing
    end

    test "explicit parent: override skips walk" do
      compiled = Sibling.__witness_compiled__()
      assert compiled.parent == Root
      assert compiled.repos == [Witness.InMemory]
      assert compiled.domain == :billing
    end
  end
end
