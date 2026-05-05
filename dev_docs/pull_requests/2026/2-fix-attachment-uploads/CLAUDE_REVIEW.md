# Claude's Review of PR #2 — Fix ticket attachment upload pipeline

**Verdict:** Approved post-merge — the four bug fixes are real and correct, but the chosen fix-shape (consume in `progress` callback) introduces a new orphan-file failure mode in Storage and triples the duplication of the consume block across three LiveViews. The duplication, the silent-failure UX, the `target="_blank"` hygiene, and the spec gap were fixed in this same review (see "Follow-up commit" below); the orphan-file and MIME-trust issues remain open for a future PR.

**Reviewed:** 2026-05-05
**Reviewer:** Claude (claude-opus-4-7)
**PR:** https://github.com/BeamLabEU/phoenix_kit_customer_support/pull/2
**Author:** Tymofii Shapovalov (timujinne)
**Head SHA:** e0189e8
**Status:** Merged (06ffdce)

## Follow-up commit (post-merge fixes by reviewer)

Applied during this review against `main` after merge — separate from Tim's PR:

- **Extracted `Uploads.consume_entry/4` and `Uploads.cancel_errored_entries/2`** (`lib/phoenix_kit_customer_support/uploads.ex`). The six near-identical consume blocks in `Web.New`, `Web.UserNew`, `Web.UserDetails` collapsed to one helper call each. `do_process_uploads` and `process_pending_uploads` deleted from all three LiveViews — the `progress` callback covers the flow; the save handler now only calls `Uploads.cancel_errored_entries/2` (via a small `maybe_cancel_errored/1` guard) to clear errored entries from the upload UI before navigating away. Net: ~160 LOC removed.
- **Storage failures are no longer silent.** `Uploads.consume_entry/4` returns `{:error, client_name}` when the storage call resolves to `nil`. Each LiveView pushes a translated message into the existing `:upload_errors` assign, and `web/user_new.html.heex` + `web/user_details.html.heex` now render that list (the assign existed but wasn't surfaced; `web/new.html.heex` was already wired). `Web.UserDetails` mount also picked up the `:upload_errors` assign, which it was missing.
- **`rel="noopener noreferrer"` added** to all three `<a target="_blank">` attachment links — the one PR #2 added in `details.html.heex:66`, plus the two pre-existing in `user_details.html.heex:72,94` (those predated PR #2 but had the same gap).
- **`@spec file_type_from_mime/1`** widened from `String.t() | nil` to `term()` to match the catch-all clause.

**Skipped (need design):**

- Storage orphan-file leak on `remove_pending_file` and abandon-and-navigate. `Storage.delete_file_completely/1` exists but the per-user-checksum dedupe in `store_file_in_buckets` means one Storage row may be referenced by multiple `ticket_attachments`/`comment_attachments` rows; naive deletion would orphan other tickets' attachments. Wants either a reference-count check before delete, or an Oban sweep over `Storage.find_orphaned_files/1`. Not a one-line fix.
- Magic-byte MIME sniffing. `entry.client_type` still drives `file_type_from_mime/1` and therefore bucket selection / variant generation. Wants server-side sniffing in `Storage.store_file_in_buckets/6` itself, not in this package.

Verified: `mix compile --warnings-as-errors` clean, `mix format` clean.

## Summary

Fixes four genuine bugs in the ticket-attachment flow:

1. `Enum.filter(&match?({:ok, _}, &1))` against `consume_uploaded_entries/3` output never matched, because the function unwraps each `{:ok, val}` into bare `val` — every successful upload was silently dropped (`web/new.ex`, `web/user_new.ex`, `web/user_details.ex`).
2. `{:error, reason}` returned from the consume callback violates the `{:ok, term} | {:postpone, term}` contract and crashed the LiveView; the PR now logs and returns `{:ok, nil}`.
3. Calling `consume_uploaded_entries` with errored entries in the queue raised — the new `cancel_errored_entries/2` cancels `not entry.valid?` refs and `upload.errors` refs first.
4. Hardcoded `"document"` file-type meant images never got `image/*` bucket placement or thumbnail variants — replaced with `Uploads.file_type_from_mime/1` driven by `entry.client_type`.

Plus two template fixes: `file.original_name` → `file.original_file_name` (the schema field; old name raised `KeyError` and reset `pending_files`), and admin attachment tiles now wrap in `<a target="_blank">` to match user-side behaviour.

The bugs are real; the fixes are correct in the small. The structural concerns below are about the fix-shape, not the diagnoses.

## Issues

### 1. [MEDIUM] Storage orphan files: consume-on-progress changes failure mode
**Files:**
- `lib/phoenix_kit_customer_support/web/new.ex:63-111` (`handle_upload_progress/3`, `consume_done_entry/2`)
- `lib/phoenix_kit_customer_support/web/user_new.ex:62-109` (same pair)
- `lib/phoenix_kit_customer_support/web/user_details.ex:82-132` (`handle_comment_upload_progress/3`, `consume_done_comment_entry/2`)
- `lib/phoenix_kit_customer_support/web/new.ex:184-192` (`remove_pending_file` event)
- `lib/phoenix_kit_customer_support/web/user_new.ex:163-171` (same)
- `lib/phoenix_kit_customer_support/web/user_details.ex:189-199` (`remove_pending_comment_file`)

Before this PR, `consume_uploaded_entries/3` ran inside `save` — files only hit `Storage.store_file_in_buckets/6` if the user actually submitted, and abandoned uploads cleaned themselves up via LiveView's temp-file lifecycle. After this PR, the `progress` callback consumes on `entry.done?`, which means the file is permanently written to Storage the moment upload completes. Three new orphan paths result:

1. **User clicks "remove" before submit** — `remove_pending_file` only drops the UUID from `pending_file_uuids` / `pending_files`. The Storage row and the actual bucket file are *not* deleted. There is no `Storage.delete_file/1` call paired with the remove event.
2. **User navigates away without submitting** — same outcome: file stored, never linked.
3. **`max_entries` no longer caps Storage writes** — a user can drop 5 files (consumed), remove all 5, drop 5 more, repeat. Each cycle adds Storage rows. Per-user-per-file deduplication via `get_file_by_user_checksum` (`deps/phoenix_kit/.../storage.ex:2334`) bounds the leak per user-file pair, but not across distinct files.

**Risk:** Slow-bleed Storage growth tied to UI noise (drag-drop fiddling), not to actual ticket creation. Hard to notice until storage costs rise.

**Fix options:** (a) Pair `remove_pending_file` with `Storage.delete_file/1` for the file UUID — trivial. (b) Add a periodic Oban job that deletes Storage rows with no `ticket_attachments` / `comment_attachments` rows older than N hours (preferred — also handles abandon-and-navigate-away). The pre-existing per-user-checksum dedupe softens but does not close the leak.

**Confidence:** 85/100

### 2. [MEDIUM] File-type classification trusts client-provided MIME
**Files:**
- `lib/phoenix_kit_customer_support/uploads.ex:11-19`
- All three callers pass `entry.client_type` (e.g. `web/new.ex:82`, `web/new.ex:231`)

`Uploads.file_type_from_mime/1` switches on a string the browser sent — `entry.client_type` is the user-controlled `Content-Type` from the multipart upload, the same field the Phoenix-thinking gotcha calls out: "the `:content_type` in `%Plug.Upload{}` is user-provided." A malicious client can claim `image/jpeg` for any file and route it into the image bucket, where `Storage.queue_variant_generation` will hand it to the thumbnail/resize pipeline. That pipeline is downstream image processing on attacker-controlled bytes — exactly the surface that breeds image-library CVEs.

The PR is still a strict improvement over the hardcoded `"document"` (which mis-classified everything), so this is a defense-in-depth gap rather than a new vulnerability. But the right shape is to derive the bucket from real bytes.

**Fix:** Sniff magic bytes from `path` (e.g. `:file_info`, or read the first 16 bytes and match against a small whitelist), or call `MIME.from_path/1` against the *server-rewritten* extension after validation. Cross-check against `entry.client_type` and reject the upload on disagreement. Either way, the bucket-classifier should never see the raw client header.

**Confidence:** 75/100 (correct framing; concrete exploitability depends on the variant pipeline)

### 3. [LOW] Storage failures are now silent — FIXED
**Files:**
- `lib/phoenix_kit_customer_support/web/new.ex:96-99, 245-247`
- `lib/phoenix_kit_customer_support/web/user_new.ex:94-97, 224-227`
- `lib/phoenix_kit_customer_support/web/user_details.ex:114-117, 276-279`

Returning `{:ok, nil}` on storage error correctly satisfies the `consume_uploaded_entries` contract and stops the LiveView crash — that part is right. But the user-facing effect is: the upload spinner disappears, the file vanishes from the entry list, and *nothing* tells the user the file failed to store. They'll click submit thinking five files attached and walk away with three. The only signal is `Logger.error`, which the user can't see.

**Fix:** Applied in this same review — `Uploads.consume_entry/4` now returns `{:error, client_name}` on storage failure; each LiveView pushes a translated message into `:upload_errors`; `user_new.html.heex` and `user_details.html.heex` now render that list (the assign existed in `:new`'s mount but the two siblings had to add it).

**Confidence:** 80/100

### 4. [LOW] `do_process_uploads` is now mostly dead code — FIXED
**Files:**
- `lib/phoenix_kit_customer_support/web/new.ex:194-257` (`process_pending_uploads`/`do_process_uploads`)
- `lib/phoenix_kit_customer_support/web/user_new.ex:173-236` (same)
- `lib/phoenix_kit_customer_support/web/user_details.ex:225-291` (`process_comment_uploads`/`do_process_comment_uploads`)

With `auto_upload: true` plus `progress: &handle_upload_progress/3`, every `done?` entry is consumed in the progress callback. By the time `save` fires, the only entries left in `socket.assigns.uploads.attachments.entries` are (a) errored entries (handled by `cancel_errored_entries` before consume) and (b) entries that haven't reached `done?` yet (a true race — `consume_uploaded_entries` skips non-done entries). In practice `do_process_uploads` does no work in the steady state.

The duplication amplifies: each of the three LiveViews now carries the consume block twice — once in `consume_done_entry` and once in `do_process_uploads` — six near-identical blocks where one would do. That's where bugs like the original "document" hardcoding hid.

**Fix:** Applied in this same review — `Uploads.consume_entry/4` and `Uploads.cancel_errored_entries/2` now centralise the consume + cancel logic; `do_process_uploads` and `process_pending_uploads` were deleted from all three LiveViews; the save handler now only calls `maybe_cancel_errored/1` (a small per-LiveView guard around `Uploads.cancel_errored_entries/2`). Net ~160 LOC removed.

**Confidence:** 80/100 (style + future-bug-prevention, not a correctness bug today)

### 5. [LOW] `target="_blank"` without `rel="noopener noreferrer"` — FIXED
**Files:**
- `lib/phoenix_kit_customer_support/web/details.html.heex:66` (added by this PR)
- `lib/phoenix_kit_customer_support/web/user_details.html.heex:72, 94` (pre-existing — PR mirrors the existing pattern)

Reverse-tabnabbing risk. The URLs come from internal Storage so the practical risk is low, but modern browsers (Chromium ≥88, Firefox ≥79) treat `rel="noopener"` as the default *only* when the target is a new tab opened by `window.open` — `<a target="_blank">` still inherits the older permissive behaviour in some contexts and audit tools (Lighthouse, axe) flag it.

**Fix:** Applied in this same review — `rel="noopener noreferrer"` added to all three sites.

**Confidence:** 65/100

### 6. [LOW] `@spec` for `file_type_from_mime/1` is narrower than the impl — FIXED
**File:** `lib/phoenix_kit_customer_support/uploads.ex:9`

`@spec file_type_from_mime(String.t() | nil) :: String.t()` but the second clause matches `_`, so an integer or list returns `"document"` instead of failing typecheck.

**Fix:** Applied in this same review — spec widened to `term()` to match the catch-all clause; moduledoc clarifies the result is bucket-layout only, not authorization.

**Confidence:** 90/100 (trivial)

## Things that are good

- **Bug diagnoses are sharp** — the `Enum.filter(&match?({:ok, _}, &1))` mismatch is a subtle one to spot; the PR description explains *why* the filter never matched (consume_uploaded_entries unwraps `{:ok, val}`), not just that it didn't.
- **Contract compliance** — switching from `{:error, reason}` to `{:ok, nil}` in the consume callback is exactly what Phoenix LiveView's docs require. `consume_uploaded_entries/3` is documented to expect `{:ok, term} | {:postpone, term}`; the previous code violated that.
- **`cancel_errored_entries/2` is correct** — combining `upload.errors` (refs from `:not_accepted`/`:too_large`) with `for entry, not entry.valid?` covers both sources of errored refs, and `Enum.uniq` handles the overlap. `Enum.reduce(refs, socket, &cancel_upload(&2, name, &1))` is the right shape.
- **Duplicate-file handling preserved** — the `{:ok, file, :duplicate}` arity-3 branch returns `{:ok, file}`, so duplicates still get attached to the ticket. Easy to drop accidentally; not dropped here.
- **Progress callback `if entry.done?` guard** — matches LiveView's contract that `consume_uploaded_entry` requires done entries. Skipping non-done updates is the correct shape.
- **`KeyError` fix is load-bearing** — `file.original_name` vs `file.original_file_name` looks like a typo but actually crashed the LiveView post-upload, which reset `pending_files` and made files appear to vanish. The user-visible "files don't attach" symptom traces back here.
- **No new `mount/3` DB reads** — the changes don't add to the existing PR #1 Iron Law violations. (Those are still pending from the PR #1 follow-ups.)

## Recommended Priority

| Priority | Issue | Status |
|----------|-------|--------|
| P1 | Storage orphan files on remove/abandon (consume-on-progress) | Open |
| P1 | MIME classification trusts client `entry.client_type` | Open |
| P2 | Silent storage failures (no UI feedback on `{:ok, nil}`) | **FIXED** in this review |
| P2 | Dedup the 6 consume blocks → 1 helper; drop dead `do_process_uploads` | **FIXED** in this review |
| P3 | `rel="noopener noreferrer"` on attachment `target="_blank"` links | **FIXED** in this review |
| P3 | Tighten `Uploads.file_type_from_mime/1` spec or impl | **FIXED** in this review |
