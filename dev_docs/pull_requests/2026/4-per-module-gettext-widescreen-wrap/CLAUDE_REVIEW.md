# Claude's Review of PR #4 — Per-module Gettext backend + widescreen + UI gettext wrapping

**Verdict:** Approved post-merge — the gettext-backend wiring, the widescreen change, and the 17-string wrap are clean; the `@version`/CHANGELOG HARD RULE violation was reverted before merge. Two findings remain open on `main` (ru/et ticket glossary, untranslated `page_title`); the `assign_handler` findings belong to the PR #3 content that rode along in this branch — see "Post-merge status" at the end.

**Reviewed:** 2026-05-11
**Reviewer:** Claude (claude-opus-4-7)
**PR:** https://github.com/BeamLabEU/phoenix_kit_customer_support/pull/4
**Author:** Tymofii Shapovalov (timujinne)
**Branch:** `timujinne:main` → `BeamLabEU:main`
**Head SHA:** `e88c0ed` at review, `5688c7a` after the in-review revert (fork-local SHAs)
**Status:** Merged (`ceb8d28`)

**Diff:** +633 / −54 across 13 files
**Commits at review time:** 3 (`423c94a`, `db3969b`, `e88c0ed`)

---

## Verdict: ~~REQUEST CHANGES~~ → no blockers (after `5688c7a`)

Three originally-blocking items; only #1 was treated as blocking. After follow-up commit `5688c7a` the HARD RULE block is cleared and items #2 and #3 were downgraded to advisory by the orchestrator (left for the maintainer to decide on cleanup scope).

1. ~~**HARD RULE violation**~~ ✅ **Resolved in `5688c7a`** — `@version` reverted `0.1.1 → 0.1.0`, `## 0.1.1` block deleted from `CHANGELOG.md`. Both files now match upstream/main exactly.
2. **Off-topic scope creep with behavior change** *(advisory — non-gating per orchestrator)* — commit `423c94a` bundles an unrelated `assign_handler` refactor that changes user-visible status-history semantics (always log on assignment, even with no status transition) and introduces a `describe_user/1` helper. Neither is mentioned in the commit subject or PR body.
3. **Glossary inconsistency in `ru`/`et`** *(advisory — non-gating per orchestrator)* — the same concept "ticket" is rendered two different ways within the same module:
   - ru: tab labels say `Заявки`, settings page says `Тикеты/тикетам/тикетов`
   - et: tab labels say `Päringud`, settings page says `pileti/piletite/piletitele`

The gettext-backend wiring itself, the widescreen change, and the 17-string wrap (in isolation) are clean and correct. Once the three items above are addressed, this is mergeable.

---

## Counts

- **BUG - CRITICAL:** 1
- **BUG - HIGH:** 1
- **BUG - MEDIUM:** 1
- **IMPROVEMENT - HIGH:** 1
- **IMPROVEMENT - MEDIUM:** 2
- **NITPICK:** 2

---

## Findings

### BUG - CRITICAL: `@version` bump + CHANGELOG entry violate HARD RULE

- `mix.exs:4` — `@version "0.1.0"` → `"0.1.1"`
- `CHANGELOG.md:7-11` — new `## 0.1.1 - 2026-05-08` entry added

Per `/app/CLAUDE.local.md` HARD RULE — "Never bump `@version` in `mix.exs` and never write `CHANGELOG.md` entries" — applies uniformly to every `phoenix_kit_<x>` child module. The maintainer derives version bumps and CHANGELOG entries from PR commit messages at release time. Phase 2 rollout (May 8 2026) had the maintainer overwrite these on every merge before the rule was tightened.

**Fix:** revert `mix.exs:4` to `0.1.0` and remove the new section from `CHANGELOG.md`. Commit-subject lines already carry the rationale the maintainer will use.

### BUG - HIGH: `423c94a` bundles untold `assign_handler` refactor that changes status-history behavior

`lib/phoenix_kit_customer_support.ex:524-559` — commit `423c94a`, subject "Add per-module Gettext backend for sidebar tab labels", also rewrites `assign_handler` and adds a new private helper:

Before:
```elixir
if new_status do
  create_status_history(ticket.uuid, changed_by_uuid, ticket.status, new_status,
                        "Assigned to handler")
end
```

After:
```elixir
handler_label = describe_user(handler_uuid)

{from_status, to_status} =
  if new_status, do: {ticket.status, new_status}, else: {ticket.status, ticket.status}

create_status_history(ticket.uuid, changed_by_uuid, from_status, to_status,
                      "Assigned to #{handler_label}")
```

Two material behavior changes never mentioned in the commit subject, the commit body's "Changes:" bullet list, or the PR description:

1. **Status history is now created on every assignment**, including assignments where the status does not change (previously only when `new_status` was set). Every re-assignment of an in-progress / resolved / closed ticket now produces a new `status_history` row whose `from == to`. This affects retention size and the rendering contract for the status-history template (which presumably handled only transitions before).
2. **`"Assigned to handler"` is replaced with the assignee's email interpolated into the literal**, falling back to a raw UUID. This both leaks UUIDs into the UI on lookup failure and embeds untranslated English structure into a string the rest of this PR is busy translating.

**Fix:** split this refactor out of the i18n PR. It deserves its own commit/PR with a dedicated test asserting the new "always-log on assignment" contract — and the status-history template should be touched in the same PR so the consumer sees consistent rendering.

### BUG - MEDIUM: `"Assigned to #{handler_label}"` is not wrapped in gettext

`lib/phoenix_kit_customer_support.ex:539` — the new string is user-facing (rendered through `status_history.comment`) but not passed through `gettext/1`. This directly contradicts the PR goal of making the module translatable. Even the previous literal `"Assigned to handler"` had this problem — but the rewrite is the chance to fix it.

**Fix (after splitting the refactor out):** use `gettext("Assigned to %{handler}", handler: handler_label)` with `handler_label` resolved to the email when present, and the raw UUID kept out of UI:

```elixir
handler_label =
  case repo().get(PhoenixKit.Users.Auth.User, handler_uuid) do
    %{email: email} -> email
    _ -> gettext("(unknown user)")
  end
```

### IMPROVEMENT - HIGH: Glossary inconsistency — "ticket" rendered two ways within the same module

Tab labels (`lib/phoenix_kit_customer_support.ex`, msgids in `default.pot:18` / `:22`) use one term, settings labels use another:

| msgid | ru | et |
|---|---|---|
| `Tickets` (tab) | `Заявки` | `Päringud` |
| `My Tickets` (tab) | `Мои заявки` | `Minu päringud` |
| `Tickets Per Page` | `Тикетов на страницу` ❌ | `Pileteid lehel` ❌ |
| `Allow Reopening Tickets` | `…повторное открытие тикетов` ❌ | `Luba piletite taasavamine` ❌ |
| `Allow resolved or closed tickets to be reopened` | `…решённых или закрытых тикетов` ❌ | `…suletud piletite taasavamine` ❌ |
| `Allow uploading files to tickets and comments` | `…к тикетам и комментариям` ❌ | `…piletitele ja kommentaaridele` ❌ |

Users will see "Заявки" / "Päringud" in the sidebar then land on a settings page that calls the same things "тикеты" / "piletid". Pick one term per locale and use it everywhere in this module.

Recommended (matches the tab labels, which are the higher-visibility surface):

- ru: replace `тикеты`/`тикетов`/`тикетам` → `заявки`/`заявок`/`заявкам`
- et: replace `pileti`/`piletite`/`piletitele` → `päring`/`päringute`/`päringutele`

Update both `priv/gettext/ru/LC_MESSAGES/default.po` and `priv/gettext/et/LC_MESSAGES/default.po`.

### IMPROVEMENT - MEDIUM: Bare `rescue _` in `describe_user/1` masks programmer errors

`lib/phoenix_kit_customer_support.ex:552-559`:

```elixir
defp describe_user(user_uuid) when is_binary(user_uuid) do
  case repo().get(PhoenixKit.Users.Auth.User, user_uuid) do
    %{email: email} -> email
    _ -> user_uuid
  end
rescue
  _ -> user_uuid
end
```

Per AGENTS.md ("Don't add error handling … for scenarios that can't happen"), this catches every exception including `MatchError`, `ArgumentError`, etc., and silently leaks the raw UUID into UI text. `repo().get/2` returns `nil` on miss (already handled by the `case` clause) — the only realistic failure mode here is a missing `:phoenix_kit, :repo` config, which would surface elsewhere. Drop the `rescue` clause entirely or narrow it to `Ecto.QueryError`.

(Becomes moot if you adopt the `gettext("Assigned to %{handler}", …)` shape suggested under BUG - MEDIUM.)

### IMPROVEMENT - MEDIUM: `page_title` left as raw English

`lib/phoenix_kit_customer_support/web/settings.ex:18`:

```elixir
|> assign(:page_title, "Customer Support Settings")
```

The displayed h1 (heex line 4, `gettext("Customer Support Settings")`) is translated but the browser tab title is still English. Same msgid is already in the catalogues — just wrap it:

```elixir
|> assign(:page_title, gettext("Customer Support Settings"))
```

### NITPICK: `mix.lock` carries unrelated dep bumps

The PR pulls in updates for `decimal` (2.3 → 3.0), `ecto` (3.13.5 → 3.13.6), `jason` (1.4.4 → 1.4.5), `leaf` (0.2.11 → 0.2.13), `phoenix` (1.8.5 → 1.8.7), `phoenix_live_view` (1.1.28 → 1.1.30), `postgrex` (0.22.0 → 0.22.1). None of these are required by the i18n work (only `:gettext ~> 1.0` is new in `mix.exs`). They should land in a separate "Update deps" PR so the diff matches the stated scope.

If the lockfile drift is purely from `mix deps.get` during dev: `git checkout main -- mix.lock && mix deps.get` will restore the smaller set.

### NITPICK: `i18n_test.exs` reformat from `mix format` is semantics-preserving

Verified by hand-reading the new file. The multi-line wrapping in commit `e88c0ed` only re-flows long `Enum.find` calls and assertion messages; no `assert` semantics, locale value, or msgid changed. ✓

---

## Verified

- `lib/phoenix_kit_customer_support/web/settings.ex:7` correctly adds `use Gettext, backend: PhoenixKitCustomerSupport.Gettext` to override the `PhoenixKitWeb.Gettext` inherited from `use PhoenixKitWeb, :live_view`. ✓ This was a concrete pre-flight check from the orchestrator brief.
- Exactly 17 strings wrapped in `settings.html.heex` (Customer Support Settings + subtitle, Statistics, Total, Open, In Progress, Resolved, Module Configuration, Tickets Per Page, Features, Internal Notes + desc, Attachments + desc, Workflow, Allow Reopening Tickets + desc). Matches PR body claim. ✓
- All four `Tab.new!` calls (admin parent, admin tickets, settings, user dashboard) carry `gettext_backend: PhoenixKitCustomerSupport.Gettext`. ✓
- `mix.exs:58` adds `priv` to the `files:` list so `.po` catalogues actually ship to Hex consumers. ✓
- `mix.exs:28` adds `:gettext` to `extra_applications` — required so the backend's app is started under the parent app's tree. ✓
- `test/test_helper.exs:90-103` introduces `:requires_phoenix_kit_i18n_api` tag and excludes when `PhoenixKit.Dashboard.Tab.localized_label/1` isn't loaded. Clean graceful-degradation pattern for the dep that hasn't shipped to Hex yet (BeamLabEU/phoenix_kit#522 / #531).
- Glossary spot-check (passing): Statistics → `Статистика` / `Statistika`; Open → `Открытые` / `Avatud`; In Progress → `В работе` / `Töös`; Resolved → `Решено` / `Lahendatud`; Features → `Функции` / `Funktsioonid`; Internal Notes → `Внутренние заметки` / `Sisemised märkused`; Attachments → `Вложения` / `Manused`; Workflow → `Рабочий процесс` / `Töövoog`.
- `lib/phoenix_kit_customer_support/gettext.ex` is a minimal `use Gettext.Backend, otp_app: :phoenix_kit_customer_support` with helpful moduledoc. ✓
- Widescreen change (commit `db3969b`) is laser-focused: drops only the `max-w-4xl mx-auto` outer wrapper, preserves the `max-w-xs` on the `Tickets Per Page` select. ✓

---

## Recommended commit shape after fixes

1. **Revert `mix.exs` `@version`** (drop `0.1.1`) and **drop the CHANGELOG entry**.
2. **Extract** the `assign_handler` / `describe_user` refactor into its own commit/PR with:
   - status-history template handling for `from == to` rows
   - `gettext("Assigned to %{handler}", …)` wrapping
   - a dedicated test for "always log on assignment"
3. **Normalize ticket terminology** in `priv/gettext/ru/LC_MESSAGES/default.po` and `priv/gettext/et/LC_MESSAGES/default.po` (use the tab-label term throughout).
4. **Wrap `page_title`** in `web/settings.ex` with `gettext/1`.
5. **Trim `mix.lock`** back to the i18n-only delta.

Items 1, 2, 3 block merge. Items 4, 5 are quick follow-ups that can ride along.

---

## Post-merge status (added when archiving, `main` @ `a23744a`, v0.1.2)

The review was written against the fork branch before rebase. What actually landed upstream in `ceb8d28` is two commits — `4f3126d` (widescreen) and `1db424e` (gettext wrapping). The third commit reviewed here, `423c94a` ("Add per-module Gettext backend"), was a fork-local duplicate of work already merged through PR #3 as `01663b1`; it therefore carries no diff of its own in PR #4.

| Finding | Status on `main` |
|---|---|
| BUG - CRITICAL: `@version` bump + CHANGELOG entry | ✅ Reverted in-review (`5688c7a`) before merge; releases `0.1.1`/`0.1.2` are maintainer-cut |
| BUG - HIGH: bundled `assign_handler` refactor | ⚠️ Open — belongs to the PR #3 content; same finding is issue #1 in `../3-per-module-i18n/CLAUDE_REVIEW.md`, still unresolved (`lib/phoenix_kit_customer_support.ex:524-557`) |
| BUG - MEDIUM: `"Assigned to #{handler_label}"` not wrapped in gettext | ⚠️ Open — `lib/phoenix_kit_customer_support.ex:539` |
| IMPROVEMENT - HIGH: ru/et "ticket" glossary inconsistency | ⚠️ Open — `Заявки` vs `Тикетов на страницу`, `Päringud` vs `Pileteid lehel` still differ in both catalogues |
| IMPROVEMENT - MEDIUM: bare `rescue _` in `describe_user/1` | ✅ Fixed in `c192d69` (PR #3 follow-up) |
| IMPROVEMENT - MEDIUM: `page_title` left as raw English | ⚠️ Open — `lib/phoenix_kit_customer_support/web/settings.ex:18` |
| NITPICK: `mix.lock` carries unrelated dep bumps | ➖ Moot — lock has since been refreshed deliberately (`a23744a`) |
| NITPICK: `i18n_test.exs` reformat is semantics-preserving | ➖ Informational |

One line in **Verified** is stale by design: `mix.exs` package `files:` said `priv` at review time and was narrowed to `priv/gettext` afterwards in `c192d69`.
