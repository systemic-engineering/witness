defmodule Witness.MixProject do
  use Mix.Project

  @version "0.2.0"
  @source_url "https://github.com/systemic-engineer/witness"

  def project do
    [
      app: :witness,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
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
      extra_applications: [:logger]
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
      licenses: ["Hippocratic-3.0"],
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
