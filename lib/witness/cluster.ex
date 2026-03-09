defmodule Witness.Cluster do
  @moduledoc """
  Starts a named Erlang node for the current Mix project and connects
  to other nodes running on the same machine.

  Node names are derived from the Mix app name, so each repo gets a
  distinct, discoverable identity on the local BEAM network:

      glue@hostname     # when run from the glue project
      witness@hostname  # when run from the witness project

  Call `start/0` once at the beginning of `mix witness` to enable
  cross-repo clustering with zero configuration.
  """

  require Logger

  @doc "Compute the Erlang node name for a given app and hostname."
  @spec node_name(atom(), String.t()) :: node()
  def node_name(app, hostname) when is_atom(app) and is_binary(hostname) do
    :"#{app}@#{hostname}"
  end

  @doc """
  Start a named node using the Mix app name, then connect to local peers.
  No-op if distribution is already running.
  """
  @spec start() :: :ok | {:error, term()}
  def start do
    if Node.alive?() do
      :ok
    else
      app = Mix.Project.config()[:app]
      hostname = local_hostname()
      name = node_name(app, hostname)

      case :net_kernel.start([name, :shortnames]) do
        {:ok, _pid} ->
          Logger.info("Started distributed node: #{name}")
          connect_local_peers(hostname)
          :ok

        {:error, {:already_started, _pid}} ->
          :ok

        {:error, reason} ->
          Logger.warning("Could not start distribution: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  # ---------------------------------------------------------------------------

  defp local_hostname do
    {:ok, hostname} = :inet.gethostname()
    # Shortnames require no dots in the hostname part.
    hostname |> to_string() |> String.split(".") |> hd()
  end

  defp connect_local_peers(hostname) do
    hostname_charlist = to_charlist(hostname)

    case :net_adm.names(hostname_charlist) do
      {:ok, nodes} ->
        for {name, _port} <- nodes do
          peer = :"#{name}@#{hostname}"

          if peer != Node.self() do
            case Node.connect(peer) do
              true -> Logger.info("Connected to peer: #{peer}")
              false -> Logger.debug("Could not connect to #{peer} (wrong cookie or down)")
              :ignored -> :ok
            end
          end
        end

      {:error, _} ->
        Logger.debug("epmd not available or no local nodes found")
    end
  end
end
