# PR #7 Phase 1 Review — phoenix_kit_customer_support
**Title:** Stop ticket URLs moving on every status change; adopt core's put_slug/3
**Author:** Max Don (mdon)
**Verdict:** APPROVE WITH NOTES

---

## Summary

Fixes three defects in the old local slug implementation and replaces both
`maybe_generate_slug/1` and `slugify/1` with core's `Slug.put_slug/3`. The
root cause (keying on `get_change(:slug)` which is nil on status-only saves)
is correctly identified and squarely fixed. Test coverage is thorough and
verified to fail against the old code. Two housekeeping items (version bump,
CHANGELOG) are acknowledged by the author but not done — they're needed before
publish. The PR carries a hard merge sequencing constraint: it **must not land
until core PR #711 ships `put_slug/3` + V168 to Hex**.

---

## Findings

### Blockers

**B1 — Missing `@version` bump (mix.exs)**
No version increment in `mix.exs`. The PR description explicitly flags it. This
package can't be published to Hex without it. Must be resolved before the
release phase.

**B2 — Missing CHANGELOG.md entry**
No changelog update. Also noted by the author. Required before Hex publish per
project convention.

**B3 — Merge sequencing: blocked on core `put_slug/3` + V168**
Published core 2.3.0 has neither `put_slug/3` nor V168's unique slug index.
Merging before core ships means every `Ticket.changeset/2` raises
`UndefinedFunctionError` in any consumer and the `-2`-suffix collision test
additionally needs V168's unique index to pass. Do **not** merge until
BeamLabEU/phoenix_kit#711 is published. (The pin stays `~> 2.0` correctly —
this is a sequencing constraint, not a version-pin problem.)

### Non-blockers

**N1 — Verbose inline comment in `changeset/2`**
The 13-line comment block fully restates the PR description. The key point
("keeps an existing slug, romanizes, suffixes -2/-3 …") fits in two lines. The
PR body and test file already have the full explanation. Consider trimming to
the essential "why" only.

**N2 — No data migration for historically duplicate slugs**
If any production database has duplicate slug values from the pre-fix behaviour,
V168's unique index (added in core) would fail to apply during `ensure_current`
on deploy. The PR is silent on this. In practice the clock-suffix approach made
same-millisecond collisions unlikely, so this is low-risk — but worth a
conscious acknowledgement or a one-off de-dup task before deploying to prod with
the core upgrade.

### Nitpicks

- `pk_dep/3` in `mix.exs` is clean and portable. Keeping the requirement
  alongside the path override (`[path: path, override: true] ++ opts`) is the
  right call for the pin conformance test.
- Test helper fix (`PhoenixKit.Migration.ensure_current/2`) is correct: the
  tickets schema lives in core's migration chain, not this module's, so the old
  helper couldn't build it.
- Deliberately not pinning exact transliteration output in the Cyrillic test is
  the right call (good comment referencing phoenix_kit_dashboards#5).

---

## Stats

- **Tests:** 5 new tests in `ticket_slug_test.exs`; 4/5 confirmed to fail
  against old code (author verified by stashing). Suite: 12 tests, 0 failures.
- **Migrations:** None in this module (index lives in core's V168 chain).
- **Version bump:** Not done — required before Hex publish (Blocker B1).
- **Dependency changes:** `pk_dep/3` helper wraps the `phoenix_kit` dep for
  local path override via `PHOENIX_KIT_PATH`; Hex pin unchanged at `~> 2.0`.
- **Files changed:** 4 (ticket.ex, mix.exs, ticket_slug_test.exs, test_helper.exs)
- **+147 / -33 lines**
