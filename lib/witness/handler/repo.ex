defmodule Witness.Handler.Repo do
  @moduledoc """
  A handler that persists telemetry events as `Witness.Event` records
  through a `Witness.Repo`.

  Replaces the Store pipeline — the Repo IS the store.

  ## Configuration

  The handler config is a `{repo, context}` tuple where:
  - `repo` is a module that `use`s `Witness.Repo` (or any `Ecto.Repo`)
  - `context` is the `Witness` context module (used for namespace path)

  ## Example

      use Witness,
        app: :my_app,
        prefix: [:my_context],
        repo: MyApp.WitnessRepo
  """

  @behaviour Witness.Handler

  @impl Witness.Handler
  def handle_event(event_name, attributes, meta, {repo, context}) do
    data =
      JSON.encode!(%{
        event_name: event_name,
        attributes: attributes,
        meta: meta,
        timestamp: System.system_time(:microsecond)
      })

    message = build_message(context, event_name)

    event = %Witness.Event{data: data, message: message, parent: nil}
    repo.insert(event)

    :ok
  end

  defp build_message(context, event_name) do
    prefix = context_prefix(context)
    suffix = Enum.map_join(event_name, "/", &Atom.to_string/1)
    "#{prefix}#{suffix}"
  end

  defp context_prefix(context) do
    config = context.config()
    prefix_atoms = Keyword.fetch!(config, :prefix)
    Enum.map_join(prefix_atoms, "/", &Atom.to_string/1) <> "/"
  end
end
