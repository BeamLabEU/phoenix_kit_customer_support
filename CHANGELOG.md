# Changelog

All notable changes to this project will be documented in this file.

This project adheres to [Semantic Versioning](https://semver.org/).

## 0.1.1 - 2026-05-08

### Added
- Per-module Gettext backend (`PhoenixKitCustomerSupport.Gettext`) with `en`/`ru`/`et` catalogues for all admin sidebar tab labels. Requires `phoenix_kit` release that ships the `gettext_backend` Tab API ([BeamLabEU/phoenix_kit#522](https://github.com/BeamLabEU/phoenix_kit/pull/522)); on older releases tabs render raw English (graceful degradation).

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
