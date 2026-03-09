defmodule Mix.Tasks.Witness do
  @shortdoc "Start the Witness MCP server"
  @moduledoc """
  Starts the Witness observability field and runs the MCP server on stdio.

  ## Usage

      mix witness

  Starts `Witness.Server` (Mnesia store + supervision tree) and enters the
  MCP JSON-RPC loop on stdio. AI agents connect through the MCP config:

      {
        "mcpServers": {
          "witness": {
            "command": "mix",
            "args": ["witness"]
          }
        }
      }
  """

  use Mix.Task

  @gleam_packages %{
    "bias" => ~w(bias gleam_stdlib),
    "fragmentation/gleam" => ~w(fragmentation)
  }

  @impl Mix.Task
  def run(_args) do
    # Redirect logger to stderr so stdout stays clean for JSON-RPC
    Logger.configure_backend(:console, device: :standard_error)

    Mix.Task.run("app.start")

    # Gleam BEAM packages must go on the code path AFTER app.start,
    # because app.start prunes code paths not tied to OTP applications.
    ensure_gleam_code_paths()

    # Ensure Witness.Server is running (may already be in supervision tree)
    case Witness.Server.start_link() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    Witness.Server.MCP.run(:stdio)
  end

  defp ensure_gleam_code_paths do
    # Resolve the projects root from witness's dep path or source location.
    # Path deps: Mix.Project.deps_paths() returns the source path.
    # Standalone: __DIR__ is inside lib/mix/tasks/, walk up to project root.
    projects_dir =
      case Mix.Project.deps_paths()[:witness] do
        nil -> Path.expand("../../..", __DIR__)
        path -> Path.expand("..", path)
      end

    for {pkg, modules} <- @gleam_packages,
        mod <- modules do
      path = Path.join([projects_dir, pkg, "build", "dev", "erlang", to_string(mod), "ebin"])

      if File.dir?(path) do
        Code.prepend_path(String.to_charlist(path))
      end
    end
  end
end
