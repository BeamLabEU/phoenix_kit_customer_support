# PR #8 — Add module-owned migration chain V1 for the 4 ticket tables

**Reviewed:** 2026-09-16 · **Author:** Timujeen · **Verdict:** PASS — ship,
finding closed.

## What actually landed

`lib/phoenix_kit_customer_support/migrations.ex` (new), implementing
`PhoenixKitCustomerSupport.Migrations` — the same decentralized-migrations
dual-reader protocol already merged for `phoenix_kit_dashboards` (PR #11),
`phoenix_kit_warehouse` (PR #30) and `phoenix_kit_posts` (PR #20), scaled to
this module's 4 tables / 10 FKs / 1 CHECK constraint. V1 is a pure
adoption: it recognizes and idempotently re-asserts the exact shape core's
own chain already created (`V135` baseline, `V164` — a repair migration
that deliberately leaves `phoenix_kit_ticket_status_history.changed_by_uuid`
out of its NOT NULL enforcement, `V168` — makes
`phoenix_kit_tickets_slug_index` UNIQUE), then stamps a `pkcs_schema:1`
marker via `COMMENT ON TABLE` on `phoenix_kit_tickets` (the module's own hub
table, deliberately chosen over the FK-free
`phoenix_kit_ticket_status_history`, with the moduledoc explaining why).
`migration_module/0` wired on `PhoenixKitCustomerSupport`; `column_widths/0`
added to `Ticket`/`TicketStatusHistory`; three new test files;
`README.md`/`CHANGELOG.md` updated (no version bump).

## The one deliberate deviation, scrutinized hardest

`phoenix_kit_ticket_status_history.changed_by_uuid` is created **nullable**
in V1, not matching core's literal `v135.ex` source (`NOT NULL`) or the
`ExpectedSchema` manifest's structured `revisions` field (also
`not_null: true`). Both are stale/inconsistent with that column's own FK
(`ON DELETE SET NULL`). Independently re-verified, from primary sources,
not taken on the moduledoc's word:

- `v135.ex:913` literally has `"changed_by_uuid" uuid NOT NULL` — confirmed.
- `v164.ex`'s moduledoc documents this exact contradiction and lists
  `{:phoenix_kit_ticket_status_history, "changed_by_uuid"}` in
  `@relaxed_after_v57` (line 216) — confirmed.
- `expected_schema.ex`'s `create:` text for the column omits NOT NULL while
  its structured `revisions` field says `not_null: true` (~line 30271-30281)
  — the manifest's own internal inconsistency — confirmed.
- Live query against `decor_3d_print_dev` (core v190, well past this
  module's `~> 2.4` floor): `information_schema.columns` shows the column
  `is_nullable = 'YES'` today — confirmed.

Independently re-confirmed a second time by a 4-agent DDL-verification
workflow (one skeptic agent per table, told to refute rather than confirm)
— all 4 returned `confirmed`, zero discrepancies, all three sub-claims
above independently re-verified by every one of them.

## Verification

Independently re-derived, not taken from the PR body's self-report:

- **DDL shape-identity**: `CREATE TABLE` bodies for all 4 tables diffed
  against `/app/lib/phoenix_kit/migrations/postgres/v135.ex` (lines
  879-935) — exact match on every column/type/default/NOT NULL (except the
  one documented deviation above). All PK/CHECK/FK guards and all 21
  indexes grep-verified by exact name against `v135.ex`/`v164.ex`/`v168.ex`
  and cross-checked against `decor_3d_print_dev` live — no drift.
- **FK tally** (10 total: 2→`phoenix_kit_users` SET NULL from `tickets`, 3
  CASCADE to `tickets` itself, 1 self-referential on `ticket_comments`
  CASCADE, 1→`phoenix_kit_users` CASCADE from `ticket_comments`, 2 CASCADE
  from `ticket_attachments` [→`ticket_comments`, →`phoenix_kit_files`], 1→
  `phoenix_kit_users` SET NULL from `ticket_status_history`) — confirmed
  against the DDL, matches the PR body exactly.
- **1 real unique index** (`phoenix_kit_tickets_slug_index`, per V168)
  adopted as-is; confirmed UNIQUE in both `v168.ex` source and live
  `pg_indexes`.
- **`down/1` safety**: emits only `COMMENT ON TABLE` for any target,
  verified by source reading and by `migrations_data_safety_test.exs`,
  which seeds real rows (`Ticket`/`TicketComment`/`TicketStatusHistory`) via
  a real `Ecto.Migration.Runner`, proves byte-for-byte survival through
  `down(version: 0)` and a map-shaped `down(%{version: 1})`, and includes a
  `DestructiveRollback` negative control proving the survival assertions
  actually fail against a real mutant — not a tautological test.
- **`up/1` real-run coverage (the one finding, now closed)**: the initial
  pass only exercised `up/1` indirectly (`test_helper.exs` applies
  `up_statements/2` as raw SQL, bypassing `up/1`'s own
  re-read/`ensure_extension!`/`ensure_uuid_v7_function`/`execute` path).
  Commit `09b0cc0` added `RunUpToOne` + a real-run test: clears the marker
  to force the "behind target" branch, runs `up/1` via
  `Ecto.Migration.Runner`, asserts the marker lands at 1, asserts every
  seeded row survives untouched, and re-runs it to prove idempotence
  (correctly hits the already-at-target no-op branch on the second run).
  Re-verified in the diff and by re-running the full suite.
- **Docs**: `README.md`'s new "Removing this module" section gives a
  manually-verified FK-safe DROP order (attachments → comments →
  status_history → tickets last, which also drops the marker);
  `CHANGELOG.md` has a matching `## Unreleased` entry; `mix.exs` `@version`
  untouched.
- **Commit hygiene**: both commits (`b0d9a50`, `09b0cc0`) authored by
  `Timujeen <timujeen@gmail.com>`, no AI attribution, working tree clean.
  PR is draft, base `main`, targets `BeamLabEU/phoenix_kit_customer_support`.

```
$ mix format --check-formatted && mix compile --force --warnings-as-errors && mix credo --strict && mix dialyzer
363 mods/funs, found no issues.
Total errors: 0, Skipped: 0, Unnecessary Skips: 0
done (passed successfully)

$ MIX_ENV=test PGDATABASE=phoenix_kit_customer_support_test PGHOST=postgres mix test
Running ExUnit with seed: 0, max_cases: 8
.....................................................
Finished in 3.5 seconds (2.0s async, 1.4s sync)
53 tests, 0 failures
```

`mix precommit` fails only on a pre-existing `mix hex.audit` advisory
(`mint` CVE) — confirmed present on a pristine `upstream/main` checkout
with none of this PR's changes applied (stashed the diff, re-ran
`hex.audit` against the base branch directly, identical two advisories).
Not a defect this PR introduces or should fix by bumping an unrelated
transitive dependency pin.

## Findings

One **MINOR** in the initial pass (`up/1` never exercised through a real
migration run) — fixed in commit `09b0cc0`, re-reviewed, closed. No
`BUG`, no other `IMPROVEMENT`, no `NITPICK`. Both spec-compliance and
code-quality stages PASS.
