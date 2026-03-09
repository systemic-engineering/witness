defmodule Witness.Cluster do
  @moduledoc """
  Starts a named Erlang node for the current Mix project and connects
  to other nodes running on the same machine.

  Node names are derived from the Mix app name, so each repo gets a
  distinct, discoverable identity on the local BEAM network:

      glue@hostname     # when run from the glue project
      witness@hostname  # when run from the witness project

  If the primary name is already taken (e.g. the deployed app is running),
  a satellite node is started instead:

      glue-/path/to/glue-<uuid>@hostname

  The satellite connects to the primary, joining its observability field
  rather than creating an isolated silo.

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
  Compute the primary node name, respecting the `WITNESS_NODE` override.

  Set `WITNESS_NODE=production-glue@prod-host` to point `mix witness` at a
  specific deployed node rather than deriving the name from the Mix app.
  """
  @spec primary_node_name(atom(), String.t()) :: node()
  def primary_node_name(app, hostname) do
    case System.get_env("WITNESS_NODE") do
      nil -> node_name(app, hostname)
      override -> String.to_atom(override)
    end
  end

  @doc """
  Compute a satellite node name: `app-pwd-uuid@hostname`.

  Used when the primary node name is already taken, typically because the
  deployed app is running. The satellite joins the primary's cluster instead
  of competing for its identity.
  """
  @spec satellite_node_name(atom(), String.t(), String.t(), String.t()) :: node()
  def satellite_node_name(app, pwd, uuid, hostname)
      when is_atom(app) and is_binary(pwd) and is_binary(uuid) and is_binary(hostname) do
    :"#{app}-#{pwd}-#{uuid}@#{hostname}"
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
      name = primary_node_name(app, hostname)

      case :net_kernel.start([name, :shortnames]) do
        {:ok, _pid} ->
          Logger.info("Started distributed node: #{name}")
          connect_local_peers(hostname)
          :ok

        {:error, {:already_started, _pid}} ->
          :ok

        {:error, _} ->
          # Primary name taken — likely the deployed app. Start as satellite.
          start_satellite(app, hostname, name)
      end
    end
  end

  defp start_satellite(app, hostname, primary) do
    pwd = System.get_env("PWD") || File.cwd!()
    uuid = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
    satellite = satellite_node_name(app, pwd, uuid, hostname)

    case :net_kernel.start([satellite, :shortnames]) do
      {:ok, _pid} ->
        Logger.info("Started satellite node: #{satellite} → #{primary}")
        Node.connect(primary)
        connect_local_peers(hostname)
        :ok

      {:error, {:already_started, _pid}} ->
        :ok

      {:error, reason} ->
        Logger.warning("Could not start distribution: #{inspect(reason)}")
        {:error, reason}
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
