defmodule PhoenixKitCustomerSupport.MixProject do
  use Mix.Project

  @version "0.1.2"
  @source_url "https://github.com/BeamLabEU/phoenix_kit_customer_support"

  def project do
    [
      app: :phoenix_kit_customer_support,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      description: "Customer support ticketing module for PhoenixKit",
      package: package(),
      dialyzer: [plt_add_apps: [:phoenix_kit]],
      name: "PhoenixKitCustomerSupport",
      source_url: @source_url,
      homepage_url: @source_url,
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :gettext, :phoenix_kit]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [
      quality: ["format", "credo --strict", "dialyzer"],
      "quality.ci": ["format --check-formatted", "credo --strict", "dialyzer"],
      precommit: [
        "compile --force --warnings-as-errors",
        "deps.unlock --check-unused",
        # Scan for retired Hex deps. Run via `cmd` so Hex bootstraps in a fresh
        # process — the hex.* archive tasks aren't resolvable via Mix.Task.run
        # inside an alias.
        "cmd mix hex.audit",
        "quality.ci"
      ]
    ]
  end

  defp deps do
    [
      # Core pin spans majors on purpose. `~> 1.7.189` means `>= 1.7.189 and
      # < 1.8.0`, which core 2.0.0 cannot satisfy — a host on `{:phoenix_kit,
      # "~> 2.0"}` plus this module is an unsolvable dependency set and
      # `mix deps.get` fails outright, with no degraded mode. 1.7.189 stays the
      # floor (Tab gettext_backend API); the ceiling moves to the next major.
      # Nothing here touches migration internals, so the widening is the whole
      # change — see the "Feature modules need a widened pin" note in core's
      # 2.0.0 CHANGELOG.
      {:phoenix_kit, ">= 1.7.189 and < 3.0.0"},
      {:gettext, "~> 1.0"},
      {:phoenix_live_view, "~> 1.1"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib priv/gettext .formatter.exs mix.exs README.md CHANGELOG.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: ["README.md", "CHANGELOG.md", "LICENSE"]
    ]
  end
end
