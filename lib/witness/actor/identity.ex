if Code.ensure_loaded?(Ecto.Schema) do
  defmodule Witness.Actor.Identity do
    @moduledoc """
    Ecto schema representing a fragmentation actor's identity.

    The Elixir-side representation of a fragmentation `Actor` — the identity
    metadata that gets written to git commits as author/committer and is
    queryable through `Witness.Repo`.

    ## Fields

      - `sha`     — content address (primary key, computed by adapter)
      - `name`    — actor name (e.g. "reed")
      - `email`   — actor email (e.g. "reed@systemic.engineer")
      - `encoder` — encoding module name or nil
      - `decoder` — decoding module name or nil
      - `keys`    — key reference or nil
    """

    use Ecto.Schema

    @primary_key false

    schema "identities" do
      field(:sha, :string, primary_key: true, read_after_writes: true)
      field(:name, :string)
      field(:email, :string)
      field(:encoder, :string)
      field(:decoder, :string)
      field(:keys, :string)
    end
  end
end
