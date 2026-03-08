if Code.ensure_loaded?(Ecto.Schema) do
  defmodule Witness.Store.Ecto do
    @moduledoc """
    Ecto-backed store adapter for Witness.

    Persists telemetry events via a configured `Ecto.Repo`. Events are stored as
    content-addressed commits — same data always produces the same SHA.

    The `:message` field carries the witness namespace path (e.g.
    `"witness/actors/alex/document/witnessed"`), which becomes the git ref path
    when using a git-backed adapter.

    Only compiled when Ecto is available. Add `{:ecto, "~> 3.12"}` to your
    project's dependencies to use this store.

    ## Configuration

        use Witness,
          app: :my_app,
          prefix: [:witness],
          store: {Witness.Store.Ecto, repo: MyApp.Repo}
    """

    @behaviour Witness.Store

    @impl Witness.Store
    def store_event(event_name, attributes, meta, context, config) do
      repo = Keyword.fetch!(config, :repo)

      data =
        JSON.encode!(%{
          event_name: event_name,
          attributes: attributes,
          meta: meta,
          timestamp: System.system_time(:microsecond)
        })

      message = build_message(context, event_name)

      event = struct!(Witness.Store.Ecto.Event, data: data, message: message, parent: nil)

      case repo.insert(event) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end

    @impl Witness.Store
    def list_events(context, _query_opts, config) do
      repo = Keyword.fetch!(config, :repo)

      # ETS adapter only supports lookup by SHA — scan the table directly
      table = repo.config()[:otp_app] || :fragmentation_repo

      events =
        try do
          :ets.tab2list(table)
          |> Enum.map(fn {_sha, fields} ->
            %{
              sha: Keyword.get(fields, :sha),
              data: Keyword.get(fields, :data),
              message: Keyword.get(fields, :message),
              parent: Keyword.get(fields, :parent)
            }
          end)
          |> Enum.filter(fn event ->
            prefix = context_prefix(context)
            String.starts_with?(event.message || "", prefix)
          end)
        rescue
          ArgumentError -> []
        end

      {:ok, events}
    end

    @impl Witness.Store
    def child_spec(config) do
      context = Keyword.fetch!(config, :context)

      # No-op — the Repo is supervised elsewhere
      %{
        id: {__MODULE__, context},
        start: {Function, :identity, [:ignore]},
        type: :worker
      }
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
end
