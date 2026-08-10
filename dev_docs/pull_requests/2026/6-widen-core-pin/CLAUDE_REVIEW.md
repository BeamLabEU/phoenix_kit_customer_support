# PR #6 — Widen phoenix_kit pin to span core majors

**Reviewed:** 2026-08-10 · **Author:** timujinne · **Verdict:** merged, with the
pin decision overridden on `main`.

Reviewed as part of the phoenix_kit 2.0 ecosystem sweep. Released in **0.2.0**.

## What it proposed

Change the core requirement from `~> 1.7.189` to `>= 1.7.189 and < 3.0.0`, so
that a single release of this module resolves against both core 1.7 and core
2.x. Plus three unrelated carries: a new `test/core_pin_conformance_test.exs`,
a README line stating the supported core range, a `@moduledoc` fix on
`TicketAttachment` (`PhoenixKit.Storage.File` → `PhoenixKit.Modules.Storage.File`,
matching what the `belongs_to` on the same schema already used), and the PR #4
review archive.

## The diagnosis is correct; the remedy was overridden

The PR's analysis is right and worth keeping on record: `~> 1.7.189` expands to
`>= 1.7.189 and < 1.8.0`, so no core 2.x satisfies it, and a host that wants
`{:phoenix_kit, "~> 2.0"}` alongside this module gets an unsolvable dependency
set — `mix deps.get` fails outright with no degraded mode. That is exactly the
problem this sweep exists to fix, and core's own 2.0.0 CHANGELOG calls it out
under "Feature modules need a widened pin".

Where this lands differently: the umbrella-wide decision for the 2.0 sweep is a
**2.0-only `~> 2.0`**, not a range spanning both majors. Requiring 2.0 rather
than merely tolerating it is the point — it makes "this module is verified
against the squashed-migration baseline" a statement the resolver enforces,
rather than leaving hosts on a core 1.7 that this module is no longer tested
against. So `main` carries `{:phoenix_kit, "~> 2.0"}`.

## What was kept, and what was adapted

**Kept as-is:** the `TicketAttachment` moduledoc fix (a genuine stale reference
to a module that exists in no current core), the PR #4 review archive, and the
idea of a committed test guarding the pin.

**Adapted:** `core_pin_conformance_test.exs` was written to assert the pin
*spans majors* — `@must_admit ["1.7.189", …, "2.3.1"]`. Under `~> 2.0` those
assertions invert, so the test was rewritten around the contract that actually
applies. It still earns its place, because `~> 2.0` has its own re-narrowing
trap: a three-segment `~> 2.0.x` expands to `< 2.1.0` and silently excludes
every later core minor. The test now admits `2.0.0`/`2.0.7`/`2.1.0`/`2.9.4` and
rejects `1.7.189`/`1.7.236`/`1.9.4`/`3.0.0`. Its central insight is preserved
verbatim: re-narrowing the pin breaks *consumers'* dependency resolution and
would never fail this repo's own test run, so nothing else would notice.

**Adapted:** the README line, which stated the old range.

## Verification

| Check | Result |
|---|---|
| `mix precommit` | **passes** against core 2.0.0 |
| `mix test` | **7 tests, 0 failures** (integration excluded — no Postgres available) |
