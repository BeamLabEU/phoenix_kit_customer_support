# PR #7 Review — Stop ticket URLs moving on every status change; adopt core's `put_slug/3`

**Author:** Max Don (@mdon)
**Reviewer:** Claude (Anthropic)
**Status:** Merged — post-merge review, fixes applied on `main`
**PR:** https://github.com/BeamLabEU/phoenix_kit_customer_support/pull/7
**Merge:** `f238c8b` (`56d4e15`)
**Date:** 2026-08-14

> Prior review in this directory: [`phase1.md`](phase1.md) (APPROVE WITH NOTES).
> Phase 1 called the missing version bump, missing CHANGELOG, and the
> `put_slug/3` merge-sequencing constraint blockers. Core 2.4.0 has since
> shipped `put_slug/3` + V168 (and this repo's lock is on 2.6.0), so the
> sequencing gate is closed. The pin was left at `~> 2.0`; that is now a
> release blocker rather than a sequencing note.

---

## Verdict

The diagnosis is correct and the replacement is the right shape:
`Slug.put_slug(:title, max_length: 255)` is exactly the changeset glue the
two local functions got wrong. Existing slugs survive a status-only save
(the headline bug), new tickets get a clean romanized title slug, and
collisions suffix `-2` against the unique index V168 added. The five
integration tests lock that in.

One release blocker the PR knowingly deferred (`~> 2.0` against an API that
landed in 2.4.0), plus a few small tightenings applied in this review.

---

## Findings

### BUG — HIGH: the `:phoenix_kit` floor admitted cores without `put_slug/3`

**Files:** `mix.exs`, `test/core_pin_conformance_test.exs`, `README.md`

`mix.exs` shipped `pk_dep(:phoenix_kit, "~> 2.0")` while `Ticket.changeset/2`
now calls `PhoenixKit.Utils.Slug.put_slug/3`, which core added in **2.4.0**.
Core's own 2.4.0 release note says it outright:

> Adopters must pin **`{:phoenix_kit, "~> 2.4"}`**: `~> 2.0` resolves to a
> core without this function, and the failure lands in the consumer's app.

A host resolving `phoenix_kit 2.0`–`2.3` alongside this package compiles
clean and then raises `UndefinedFunctionError` on **every ticket create and
every ticket update**. This repo's own suite never catches it because the
lock resolves 2.6.0. V168 (the unique `phoenix_kit_tickets_slug_index`) is
in the same 2.4.0 chain, so the `-2` collision path is equally unavailable
below that floor.

The pin-conformance test encoded "keep two segments" as "admit 2.0.0",
which is a different and now-false claim. `~> 2.4` is still two-segment and
admits every later 2.x.

**Fixed** — floor raised to `~> 2.4`; the conformance test now admits
`2.4.0`/`2.4.9`/`2.5.0`/`2.9.4` and rejects `2.0.0`/`2.3.9` (and 1.x / 3.x).
Same shape as `phoenix_kit_publishing` 0.6.0.

### IMPROVEMENT — MEDIUM: a title that slugifies to empty passed the changeset

**File:** `lib/phoenix_kit_customer_support/ticket.ex`

`slug` is `varchar(255) NOT NULL`. `put_slug/3` deliberately leaves the
changeset alone when the source romanizes to `""` rather than writing a
blank that the next save would read as "no slug yet". Combined with no
`validate_required(:slug)` *after* generation, a punctuation-only title
produced a valid changeset with `slug: nil` and then a raw
`not_null_violation` at insert.

**Fixed** — `validate_required([:slug])` and `validate_length(:slug, max: 255)`
run after `put_slug/3`. A punctuation-only title now fails on `:slug`.
Generation stays *before* that require, so a create without an explicit
slug is not rejected before it can be supplied (the dead-generator trap
`phoenix_kit_publishing` #41 hit).

### IMPROVEMENT — LOW: verbose inline comment; leftover private-functions header

**File:** `lib/phoenix_kit_customer_support/ticket.ex`

The 13-line comment restated the PR body. Trimmed to the essential why
(keep existing; romanize; suffix against V168) plus the ordering
constraint on `validate_required(:slug)`. Removed the empty
`# Private Functions` header left after deleting `maybe_generate_slug/1`
and `slugify/1`.

### IMPROVEMENT — LOW: unused alias; missing title-change and lookup tests

**Files:** `test/phoenix_kit_customer_support/ticket_slug_test.exs`,
`test/phoenix_kit_customer_support/ticket_slug_changeset_test.exs`

`alias Ecto.Changeset` was unused. The integration file covered status
edits and a description edit of a *legacy* slug, but not a title change
of a newly generated slug — the case `put_slug/3`'s own docs call out as
the URL-moving failure. `get_ticket_by_slug/2` (the public lookup that
`repo().one()`s and is why uniqueness matters) was untested.

**Fixed** — title-change and `get_ticket_by_slug/2` integration tests;
new changeset-only file that always runs (no Postgres) for "existing slug
survives status/title edits", "explicit slug wins", and "punctuation-only
title fails on `:slug`".

### NITPICK: `get_ticket_by_slug/2` example still showed a timestamp suffix

**File:** `lib/phoenix_kit_customer_support.ex`

Example updated from `"cannot-login-123456"` to
`"cannot-login-to-my-account"`.

---

## Noted, not changed

- **This package's own LiveViews never put the slug in the URL.** Admin and
  user routes are `/tickets/:id` and every `push_navigate` / `navigate`
  uses `ticket.uuid`. The stored slug is still a public identifier
  (`get_ticket_by_slug/2`) and a unique column; churning it on every
  status save was a real bug even if the in-package UI was insulated.
  Not a defect in the PR — the claim is slightly broader than the routes
  this repo owns.
- **No data migration for historically duplicate slugs (phase1 N2).** V168
  in core suffixes the newer row before building the unique index. That
  is core's job and it is already written. Existing timestamped slugs are
  left as-is, which is the point of the URL-stability fix.
- **`pk_dep/3` is kept.** Useful for `PHOENIX_KIT_PATH` against uncommitted
  core; it preserves the version requirement so the pin test still sees
  it (this repo's variant is stricter than siblings that drop the
  requirement on a path override).

---

## Follow-up commit (post-merge fixes)

Applied on `main` during this review, released in **0.3.0**:

- `:phoenix_kit` floor `~> 2.0` → `~> 2.4`
- `validate_required([:slug])` + `validate_length(:slug, max: 255)` after
  `put_slug/3`
- Trimmed comment, dropped empty private-functions header
- Changeset-only slug tests; title-change + `get_ticket_by_slug/2`
  integration tests; `version/0` sync test
- README / pin-conformance test / CHANGELOG / `@version` + `version/0`

---

## Verification

| Check | Result |
|---|---|
| `mix format` | applied |
| `mix precommit` | **passes** (compile --warnings-as-errors, hex.audit, credo --strict, dialyzer) |
| `mix test` | **19 tests, 0 failures** (integration included — Postgres available) |
