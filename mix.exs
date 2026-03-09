defmodule Witness.MixProject do
  use Mix.Project

  @version "0.4.0"
  @source_url "https://github.com/systemic-engineer/witness"

  # Gleam packages are pre-built with `gleam build --target erlang`.
  # Their BEAM output goes on the code path so Elixir can call them.
  @gleam_packages [
    {"../bias", ~w(bias gleam_stdlib)},
    {"../fragmentation/gleam", ~w(fragmentation)}
  ]

  for {pkg, modules} <- @gleam_packages,
      mod <- modules do
    path = Path.expand(pkg <> "/build/dev/erlang/#{mod}/ebin", __DIR__)
    if File.dir?(path), do: Code.prepend_path(String.to_charlist(path))
  end

  def project do
    [
      app: :witness,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      prune_code_paths: false,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.json": :test
      ],
      dialyzer: [
        plt_add_apps: [:mix],
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :mnesia]
    ]
  end

  defp deps do
    [
      # Core dependencies
      {:telemetry, "~> 1.2"},
      {:nimble_options, "~> 1.1"},

      # OpenTelemetry integration — optional: only required when using Witness.Handler.OpenTelemetry
      {:opentelemetry_api, "~> 1.4", optional: true},
      {:opentelemetry, "~> 1.5", only: [:dev, :test], optional: true},
      {:opentelemetry_exporter, "~> 1.10", only: [:dev, :test], optional: true},
      {:opentelemetry_telemetry, "~> 1.1", optional: true},

      # Ecto store — compiled when Ecto is available in the consumer.
      # optional: true means witness compiles without it; the Code.ensure_loaded?
      # guard in ecto.ex/event.ex skips compilation when Ecto isn't present.
      {:ecto, "~> 3.12", optional: true},
      {:fragmentation_repo, path: "../fragmentation-repo", optional: true, only: :test},

      # Development and testing
      {:excoveralls, "~> 0.18", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.31", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    """
    An opinionated observability library built on :telemetry with compile-time event
    registry, zero-duplication event tracking, and OpenTelemetry integration.
    """
  end

  defp package do
    [
      licenses: ["SEL-1.0"],
      links: %{
        "GitHub" => @source_url
      },
      files: ~w(lib .formatter.exs .credo.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "Witness",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras: ["README.md", "CHANGELOG.md", "LICENSE"]
    ]
  end
end
