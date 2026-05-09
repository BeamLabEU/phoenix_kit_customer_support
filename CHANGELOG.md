# Changelog

All notable changes to this project will be documented in this file.

This project adheres to [Semantic Versioning](https://semver.org/).

## 0.1.1 - 2026-05-05

### Fixed

- **Ticket attachment uploads** (#2) — successful uploads were silently dropped because `Enum.filter(&match?({:ok, _}, &1))` against `consume_uploaded_entries/3` output never matched (the function unwraps `{:ok, val}` into bare `val`).
- **Storage error crash** — returning `{:error, reason}` from the `consume_uploaded_entries/3` callback violates the `{:ok, term} | {:postpone, term}` contract and crashed the LiveView.
- **Hang on invalid file type** — errored upload entries (`:not_accepted`, `:too_large`) now get cancelled before `consume_uploaded_entries/3`, which previously raised on them.
- **`KeyError` after upload** — `file.original_name` → `file.original_file_name` in the admin pending-files list (the schema field name; the old reference crashed the LiveView and reset `pending_files`).
- **Image classification** — files were hardcoded as `"document"`, so images never got bucket placement or thumbnail variants. Now classified via `PhoenixKitCustomerSupport.Uploads.file_type_from_mime/1` from `entry.client_type`.

### Changed

- Uploads are consumed in the LiveView `progress` callback (`auto_upload: true`), so files appear in "Attached files" immediately after drop instead of staying in "Uploading…" until form submit.
- Admin attachment tiles wrap in `<a target="_blank" rel="noopener noreferrer">` to match user-side behaviour and click through to the original file.
- Storage errors now surface in the UI via `:upload_errors` instead of being logged-only.
- Internal: extracted `PhoenixKitCustomerSupport.Uploads.consume_entry/4` and `cancel_errored_entries/2` to deduplicate the upload pipeline across `Web.New`, `Web.UserNew`, and `Web.UserDetails` (~160 LOC removed).

## 0.1.0 - 2026-05-04

Initial release of PhoenixKit Customer Support as a standalone Hex package, extracted from PhoenixKit core (>= 1.7.104).

### Features

- **Ticket lifecycle** — `open → in_progress → resolved → closed` with full status-history audit trail (`PhoenixKitCustomerSupport.TicketStatusHistory`).
- **Comments and internal notes** — public comments visible to ticket owners, plus agent-only internal notes gated by the `customer_support_internal_notes_enabled` setting.
- **Attachments** — file uploads on tickets and comments via `PhoenixKit.Modules.Storage`, configurable through `customer_support_attachments_enabled`.
- **Assignment** — assign tickets to support staff; assignment changes are recorded.
- **Reopen flow** — closed tickets can be reopened by users or agents when `customer_support_allow_reopen` is `true`.
- **Admin LiveViews** — list / new / edit / details / settings under `/admin/customer-support` and `/admin/settings/customer-support`.
- **User-dashboard LiveViews** — list / new / details for the ticket owner under `/dashboard/customer-support/tickets` (routes wired by `PhoenixKitWeb.Integration` in core via `Code.ensure_loaded?` guards).
- **PubSub events** — `PhoenixKitCustomerSupport.Events` exposes per-user, per-ticket, and global topics for real-time updates.
- **Module auto-discovery** — implements `PhoenixKit.Module`; registered with PhoenixKit's module system at compile time, no manual router wiring required.

### Settings keys

| Key | Default | Description |
|-----|---------|-------------|
| `customer_support_enabled` | `false` | Enables the module globally. |
| `customer_support_per_page` | `20` | Tickets per page in admin and user list views. |
| `customer_support_comments_enabled` | `true` | Allow comments on tickets. |
| `customer_support_internal_notes_enabled` | `true` | Allow agent-only internal notes. |
| `customer_support_attachments_enabled` | `true` | Allow file attachments on tickets and comments. |
| `customer_support_allow_reopen` | `true` | Allow reopening of closed tickets. |

### Migration notes (from PhoenixKit core)

PhoenixKit core's V109 migration renames the legacy keys so existing installs migrate cleanly:

- Settings keys: `customer_service_*` → `customer_support_*`
- Permission key (`phoenix_kit_role_permissions.module_key`): `customer_service` → `customer_support`
- Routes: `/customer-service/*` → `/customer-support/*`
- Module: `PhoenixKitCustomerService` → `PhoenixKitCustomerSupport`
- Hex package: `phoenix_kit_customer_support`

Run `mix phoenix_kit.update` after upgrading core to apply V109.
