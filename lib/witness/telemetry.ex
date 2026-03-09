defmodule Witness.Telemetry do
  @moduledoc """
  Attaches telemetry handlers that write events to configured repos.

  Used by `Witness.Code` to wire compile-time telemetry events into
  `Witness.Repo` instances. Each attached handler writes a `%Witness.Event{}`
  to every repo in the list on every matching event.

  Attaching to an empty repo list is a no-op. Attaching the same event twice
  is idempotent.
  """

  def attach(_event_name, []), do: :ok

  def attach(event_name, repos) when is_list(repos) do
    handler_id = {__MODULE__, event_name}

    case :telemetry.attach(handler_id, event_name, &handle_event/4, repos) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
    end
  end

  defp handle_event(event_name, measurements, metadata, repos) do
    message = Enum.join(event_name, "/")

    data =
      JSON.encode!(%{
        measurements: measurements,
        metadata: inspect_values(metadata)
      })

    for repo <- repos do
      repo.insert(%Witness.Event{data: data, message: message})
    end
  end

  defp inspect_values(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {k, if(is_atom(v), do: inspect(v), else: v)} end)
  end

  defp inspect_values(other), do: other
end
