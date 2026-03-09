defmodule Witness.Actor.IdentityTest do
  use ExUnit.Case, async: true

  describe "%Witness.Actor.Identity{}" do
    test "can be created with name and email" do
      identity = %Witness.Actor.Identity{
        name: "reed",
        email: "reed@systemic.engineer"
      }

      assert identity.name == "reed"
      assert identity.email == "reed@systemic.engineer"
    end

    test "has nil defaults for encoder, decoder, keys" do
      identity = %Witness.Actor.Identity{
        name: "reed",
        email: "reed@systemic.engineer"
      }

      assert identity.encoder == nil
      assert identity.decoder == nil
      assert identity.keys == nil
    end

    test "sha is nil by default (computed on insert)" do
      identity = %Witness.Actor.Identity{
        name: "reed",
        email: "reed@systemic.engineer"
      }

      assert identity.sha == nil
    end

    test "is an Ecto schema" do
      assert Witness.Actor.Identity.__schema__(:source) == "identities"
      assert :sha in Witness.Actor.Identity.__schema__(:fields)
      assert :name in Witness.Actor.Identity.__schema__(:fields)
      assert :email in Witness.Actor.Identity.__schema__(:fields)
    end
  end
end
