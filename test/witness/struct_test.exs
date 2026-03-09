defmodule Witness.StructTest do
  use ExUnit.Case, async: true

  describe "%Witness{}" do
    test "can be created with required fields" do
      witness = %Witness{module: MyApp.Context, prefix: [:my_app]}

      assert witness.module == MyApp.Context
      assert witness.prefix == [:my_app]
    end

    test "enforces :module and :prefix keys" do
      assert_raise ArgumentError, ~r/:module/, fn ->
        struct!(Witness, prefix: [:test])
      end

      assert_raise ArgumentError, ~r/:prefix/, fn ->
        struct!(Witness, module: MyApp)
      end
    end

    test "has correct defaults" do
      witness = %Witness{module: MyApp, prefix: [:test]}

      assert witness.parent == nil
      assert witness.domain == nil
      assert witness.span == nil
      assert witness.identity == nil
      assert witness.session == nil
      assert witness.head == nil
      assert witness.t0 == 0
      assert witness.repos == []
      assert witness.supervise == false
      assert witness.snitch == false
      assert witness.events == []
      assert witness.children == []
    end

    test "can hold an identity and session" do
      identity = %Witness.Actor.Identity{name: "reed", email: "reed@systemic.engineer"}
      session = Witness.Session.new(%{author: "reed@systemic.engineer", name: "reed"})

      witness = %Witness{
        module: MyApp,
        prefix: [:test],
        identity: identity,
        session: session,
        head: "abc123"
      }

      assert witness.identity == identity
      assert witness.identity.name == "reed"
      assert %Witness.Session{} = witness.session
      assert witness.head == "abc123"
    end

    test "is a map (backward compatible with map access)" do
      witness = %Witness{module: MyApp, prefix: [:test], t0: 42, events: [:a]}

      assert is_map(witness)
      assert witness.t0 == 42
      assert witness.events == [:a]
    end
  end
end
