if Code.ensure_loaded?(Ecto.Schema) do
  defmodule Witness.Event do
    @moduledoc """
    Content-addressed event for Witness.

    The canonical schema for all persisted witness records — both telemetry
    events (via `Handler.Repo`) and actor ODA entries (via `Actor.bias/5`).

    The adapter computes the SHA on insert (content-addressing).

    ## Fields

      - `sha`     — content address (primary key, computed by adapter)
      - `data`    — serialized payload (JSON)
      - `message` — annotation / signal kind / namespace path
      - `parent`  — SHA of the previous event in a session chain
    """

    use Ecto.Schema

    @primary_key false
    @schema_prefix nil

    schema "events" do
      field(:sha, :string, primary_key: true, read_after_writes: true)
      field(:data, :string)
      field(:message, :string)
      field(:parent, :string)
    end
  end
end
