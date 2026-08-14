defmodule PhoenixKitCustomerSupport.CorePinConformanceTest do
  use ExUnit.Case, async: true

  @moduledoc """
  Guards the `:phoenix_kit` requirement against being re-narrowed to a
  single core MINOR.

  The trap is the three-segment form: `~> 2.4.x` expands to
  `>= 2.4.x and < 2.5.0`, so no 2.5 or later core satisfies it. The breakage
  lands on consumers, not here — a host depending on both this module and a
  newer core minor gets an unsolvable dependency set and `mix deps.get`
  fails outright, with no degraded mode. Nothing else in this repo's own
  test run would notice.

  Raising the two-segment FLOOR is allowed and required: `~> 2.4` still
  admits every later 2.x, and the floor has to track the oldest core that
  has every function this module calls. `Ticket.changeset/2` calls
  `PhoenixKit.Utils.Slug.put_slug/3`, added in core 2.4.0; core's own
  release note tells adopters to pin `~> 2.4` for exactly that reason. A
  floor left at 2.0 lets `mix deps.get` resolve a core without the function
  and moves the failure to an `UndefinedFunctionError` on the host's first
  ticket save.

  Core 1.7 is deliberately excluded: core 2.0.0 squashed the migration
  chain to a V135 floor, and this module is only verified against that
  baseline.
  """

  # Floor: core 2.4.0 (`Slug.put_slug/3` + V168 unique ticket slug).
  @floor "2.4.0"
  @must_admit ["2.4.0", "2.4.9", "2.5.0", "2.9.4"]
  @must_reject ["1.7.189", "1.7.236", "1.9.4", "2.0.0", "2.3.9", "3.0.0"]

  test "the phoenix_kit requirement admits every core 2.x at or above the floor" do
    requirement = core_requirement()

    assert match?({:ok, _parsed}, Version.parse_requirement(requirement)),
           "`:phoenix_kit` requirement #{inspect(requirement)} is not a valid version requirement"

    for version <- @must_admit do
      assert Version.match?(version, requirement),
             "`:phoenix_kit` requirement #{inspect(requirement)} rejects core #{version}. " <>
               "A pin that excludes a core minor at or above the floor breaks `mix deps.get` " <>
               "for every host running this module alongside that core. Keep it two-segment."
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
