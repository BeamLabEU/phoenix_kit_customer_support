# PR #8 — Follow-up

Post-merge review of the module-owned migration chain, with the findings
the in-PR `CLAUDE_REVIEW.md` did not catch. Landed with the 0.4.0 release
commit.

| Severity | Finding | Resolution |
|---|---|---|
| IMPROVEMENT - MEDIUM | `column_widths/0` is documented as "the single source for every varchar width this schema's changeset validates", but `Ticket.changeset/2` hard-coded `max: 255` three times (`title`, `slug`, `put_slug`'s `max_length`) and `TicketStatusHistory.changeset/2` did not length-validate `from_status`/`to_status` at all — an over-long value raised `string_data_right_truncation` at Postgres instead of returning a changeset error. The drift test only pinned the DDL side, so a width change would have silently diverged from validation. | **Fixed** — both changesets read `@column_widths`; `test/phoenix_kit_customer_support/column_widths_changeset_test.exs` (DB-free) asserts width passes and width + 1 fails with `count: width` for all 4 fields. |
| IMPROVEMENT - MEDIUM | README "Removing this module" presented `DROP TABLE` as final and `COMMENT ON TABLE … IS NULL` as a way to "stop this chain from tracking" the tables. Neither holds: core's `ExpectedSchema` still lists all 4 tables as `presence: :required`, so `mix phoenix_kit.repair` recreates them **empty**; and a cleared marker is re-stamped by the next `mix phoenix_kit.update` while the module is installed. The same defect was found and fixed in `phoenix_kit_dashboards` PR #11. SQL was also unqualified. | **Fixed** — section rewritten to match the dashboards wording; SQL schema-qualified. |
| NITPICK | Stale "no shape change" wording that commit `de48eeb` did not reach: the `### Phase 0 — this V1 adopts, and changes NOTHING` heading, `up_statements/2` ("pure adoption step"), `down_statements/2` ("V1 changes no shape of its own"), and the `migration_module/0` comment ("nothing else changes on any install"). | **Fixed** — all four now name the `changed_by_uuid` relaxation; `down_statements/2` also records why it is not reverted (post-V1 rows may hold `NULL`, so `SET NOT NULL` could fail the rollback). |
| NITPICK | Typespecs claimed `Ticket.user_uuid` and `TicketStatusHistory.changed_by_uuid` are never nil, but both FKs are `ON DELETE SET NULL` (and V1 now makes the latter actually nullable everywhere). | **Fixed** — both are `UUIDv7.t() \| nil`. |
| — | `validated_prefix/1`'s regex fallback is dead at the `~> 2.4` floor (`Helpers.validate_prefix!/1` exists in core v2.4.0). | **Not changed** — harmless, mirrors the sibling coordinators, and is covered by the prefix tests. |

## Verified non-issues

- **Core helpers exist at the floor.** `Helpers.ensure_extension!/1`,
  `ensure_uuid_v7_function/1`, `uuid_v7_call/1`, `qualify_table/2` and
  `validate_prefix!/1` are all present in core `v2.4.0`, which also ships
  `migration_module/0` discovery — so `~> 2.4` cannot resolve a core that
  discovers this chain but lacks what `up/1` calls.
- **`mix phoenix_kit.repair` does not undo the `changed_by_uuid`
  relaxation.** The manifest's `not_null: true` for that column has
  `default: nil`, which `Repair.Differ` (`reason_not_null/3`) deliberately
  excludes from comparison. `UUIDFKColumns.@not_null_uuid_fks` still lists
  the column, but only V56/V57 ran it and V164 skips it.
- **Nil `changed_by` renders.** `details.html.heex` already falls back to
  `"System"`, so a `SET NULL` history row does not crash the page.

## Gate

`mix precommit` (compile --warnings-as-errors, deps.unlock --check-unused,
hex.audit, format --check-formatted, credo --strict, dialyzer) and the full
DB-backed `mix test`: 57 tests, 0 failures.
