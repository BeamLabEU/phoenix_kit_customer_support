defmodule PhoenixKitCustomerSupport.CorePinConformanceTest do
  use ExUnit.Case, async: true

  @moduledoc """
  Guards the `:phoenix_kit` requirement against being re-narrowed to a
  single core MINOR.

  The trap is the three-segment form: `~> 3.5.x` expands to
  `>= 3.5.x and < 3.6.0`, so no 3.6 or later core satisfies it. The breakage
  lands on consumers, not here — a host depending on both this module and a
  newer core minor gets an unsolvable dependency set and `mix deps.get`
  fails outright, with no degraded mode. Nothing else in this repo's own
  test run would notice.

  The requirement is `>= 3.5.0 and < 4.0.0`. The floor is the minimum core
  every PhoenixKit module requires; it carries everything this module builds
  on: `PhoenixKit.Utils.Slug.put_slug/3` (which `Ticket.changeset/2` calls)
  and the `file_references/0` and `expected_schema/0` callbacks. The ceiling
  is open through every core 3.x.
  """

  @floor "3.5.0"
  @must_admit ["3.5.0", "3.5.1", "3.6.0", "3.9.9"]
  @must_reject ["1.7.236", "2.0.0", "2.65.0", "2.99.4", "3.0.0", "3.4.0", "3.4.9", "4.0.0"]

  test "the phoenix_kit requirement admits every core 3.x at or above the floor" do
    requirement = core_requirement()

    assert match?({:ok, _parsed}, Version.parse_requirement(requirement)),
           "`:phoenix_kit` requirement #{inspect(requirement)} is not a valid version requirement"

    for version <- @must_admit do
      assert Version.match?(version, requirement),
             "`:phoenix_kit` requirement #{inspect(requirement)} rejects core #{version}. " <>
               "A pin that excludes a core minor at or above the floor breaks `mix deps.get` " <>
               "for every host running this module alongside that core. Keep the floor " <>
               "patch-precise and the ceiling open (`>= 3.5.0 and < 4.0.0`), never a " <>
               "three-segment `~>`."
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
