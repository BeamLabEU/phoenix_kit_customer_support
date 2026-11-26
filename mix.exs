defmodule PhoenixKitCustomerSupport.MixProject do
  use Mix.Project

  @version "0.5.0"
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

  # Swaps a Hex pin for a local checkout when PHOENIX_KIT_PATH is set, so this
  # module's suite can run against uncommitted core without publishing it.
  # Unset means the published pin, so `mix hex.publish` and CI are unaffected.
  defp pk_dep(app, requirement, opts \\ []) do
    env_var = String.upcase(Atom.to_string(app)) <> "_PATH"

    case System.get_env(env_var) do
      nil when opts == [] -> {app, requirement}
      nil -> {app, requirement, opts}
      # The requirement is kept alongside the path so the pin conformance
      # test can still see it (Mix checks it against the local checkout).
      path -> {app, requirement, [path: path, override: true] ++ opts}
    end
  end

  defp deps do
    [
      # Floor 3.5.0, the minimum core every PhoenixKit module requires. It
      # carries everything this module builds on: `Utils.Slug.put_slug/3`
      # (which `Ticket.changeset/2` calls) and the `file_references/0` and
      # `expected_schema/0` callbacks.
      # Patch-precise floor in the compound form, so the ceiling stays open
      # through every core 3.x (see test/core_pin_conformance_test.exs).
      pk_dep(:phoenix_kit, ">= 3.5.0 and < 4.0.0"),
      {:gettext, "~> 1.0"},
      {:phoenix_live_view, "~> 1.1"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:lazy_html, ">= 0.1.0", only: :test}
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
