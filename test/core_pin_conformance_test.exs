defmodule PhoenixKitCustomerSupport.CorePinConformanceTest do
  use ExUnit.Case, async: true

  @moduledoc """
  Guards the `:phoenix_kit` requirement against being re-narrowed to a
  single core MINOR.

  This module requires core 2.x (`~> 2.0`). The trap the pin must avoid is
  the three-segment form: `~> 2.0.x` expands to `>= 2.0.x and < 2.1.0`, so
  no 2.1 or later core satisfies it. The breakage lands on consumers, not
  here — a host depending on both this module and a newer core minor gets
  an unsolvable dependency set and `mix deps.get` fails outright, with no
  degraded mode, and nothing in this repo's own test run would notice.

  Core 1.7 is deliberately excluded: core 2.0.0 squashed the migration
  chain to a V135 floor, and this module is only verified against that
  baseline. Nothing here touches core migration internals, so the
  requirement is the whole compatibility contract.
  """

  # Floor: core 2.0.0, the squashed-migration baseline.
  @floor "2.0.0"
  @must_admit ["2.0.0", "2.0.7", "2.1.0", "2.9.4"]
  @must_reject ["1.7.189", "1.7.236", "1.9.4", "3.0.0"]

  test "the phoenix_kit requirement admits every core 2.x" do
    requirement = core_requirement()

    assert match?({:ok, _parsed}, Version.parse_requirement(requirement)),
           "`:phoenix_kit` requirement #{inspect(requirement)} is not a valid version requirement"

    for version <- @must_admit do
      assert Version.match?(version, requirement),
             "`:phoenix_kit` requirement #{inspect(requirement)} rejects core #{version}. " <>
               "A pin that excludes a core minor breaks `mix deps.get` for every host " <>
               "running this module alongside that core. Keep it a two-segment `~> 2.0`."
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
