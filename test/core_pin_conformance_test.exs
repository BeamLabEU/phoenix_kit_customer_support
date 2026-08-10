defmodule PhoenixKitCustomerSupport.CorePinConformanceTest do
  use ExUnit.Case, async: true

  @moduledoc """
  Guards the `:phoenix_kit` requirement against being re-narrowed to a
  single core major.

  A three-segment `~> 1.7.x` pin expands to `>= 1.7.x and < 1.8.0`, which
  no 1.8 or 2.x core can satisfy. The breakage lands on consumers, not
  here: a host that depends on both this module and a newer core gets an
  unsolvable dependency set and `mix deps.get` fails outright — there is
  no degraded mode, and nothing in this repo's own test run would notice.

  Nothing in this module touches core migration internals, so spanning
  majors is safe; the requirement is the whole compatibility contract.
  """

  # Floor: PhoenixKit.Dashboard.Tab's gettext_backend API (BeamLabEU/phoenix_kit#522).
  @floor "1.7.189"
  @must_admit ["1.7.189", "1.7.236", "1.8.0", "1.9.4", "2.0.0", "2.3.1"]
  @must_reject ["1.7.188", "3.0.0"]

  test "the phoenix_kit requirement spans core majors" do
    requirement = core_requirement()

    assert match?({:ok, _parsed}, Version.parse_requirement(requirement)),
           "`:phoenix_kit` requirement #{inspect(requirement)} is not a valid version requirement"

    for version <- @must_admit do
      assert Version.match?(version, requirement),
             "`:phoenix_kit` requirement #{inspect(requirement)} rejects core #{version}. " <>
               "A pin that excludes a core major breaks `mix deps.get` for every host " <>
               "running this module alongside that core."
    end

    for version <- @must_reject do
      refute Version.match?(version, requirement),
             "`:phoenix_kit` requirement #{inspect(requirement)} admits core #{version}, " <>
               "which is outside the range this module is verified against " <>
               "(floor #{@floor}, next unreleased major excluded)."
    end
  end

  # Local development may point `:phoenix_kit` at a checkout
  # (`{:phoenix_kit, path: "/app", override: true}`), which carries no
  # version requirement to check. That form must never be committed, so
  # failing here with the reason is more useful than skipping.
  defp core_requirement do
    Mix.Project.config()
    |> Keyword.fetch!(:deps)
    |> Enum.find_value(fn
      {:phoenix_kit, requirement} when is_binary(requirement) -> requirement
      {:phoenix_kit, requirement, _opts} when is_binary(requirement) -> requirement
      _ -> nil
    end)
    |> case do
      nil ->
        raise """
        No binary version requirement found for `:phoenix_kit` in mix.exs deps.
        If this is a local path override, restore the published requirement
        before committing — see the pin comment in mix.exs.
        """

      requirement ->
        requirement
    end
  end
end
