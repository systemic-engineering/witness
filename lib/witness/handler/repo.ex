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
    {attributes, attribute_notes} = json_safe(attributes, "attributes")
    {meta, meta_notes} = json_safe(meta, "meta")

    record =
      %{event_name: event_name, attributes: attributes, meta: meta, timestamp: System.system_time(:microsecond)}
      |> then(fn r ->
        case attribute_notes ++ meta_notes do
          [] -> r
          notes -> Map.put(r, :notes, notes)
        end
      end)

    data = JSON.encode!(record)

    message = build_message(context, event_name)

    event = %Witness.Event{data: data, message: message, parent: nil}
    repo.insert(event)

    :ok
  end

  # Terms JSON can't hold (tuples such as the caller, pids, refs, functions,
  # ports) are kept as their inspected text, and their paths are listed under
  # `notes`, so nothing is dropped and nothing changes silently.
  defp json_safe(map, path) when is_map(map) and not is_struct(map) do
    Enum.reduce(map, {%{}, []}, fn {k, v}, {acc, notes} ->
      {v, more} = json_safe(v, "#{path}.#{k}")
      {Map.put(acc, k, v), notes ++ more}
    end)
  end

  defp json_safe(list, path) when is_list(list) do
    if List.improper?(list) do
      {inspect(list), [path]}
    else
      {values, notes} =
        list |> Enum.with_index() |> Enum.map(fn {v, i} -> json_safe(v, "#{path}.#{i}") end) |> Enum.unzip()

      {values, List.flatten(notes)}
    end
  end

  defp json_safe(value, _path)
       when is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value) or is_atom(value),
       do: {value, []}

  defp json_safe(value, path), do: {inspect(value), [path]}

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
