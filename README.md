# PhoenixKitCustomerSupport

Customer support ticketing module for [PhoenixKit](https://github.com/BeamLabEU/phoenix_kit).

Provides a full ticketing system: create tickets, track status, add comments and attachments, manage agents. Extracted from PhoenixKit core (>= 1.7.104).

## Installation

Add to the host app's `mix.exs`:

```elixir
{:phoenix_kit_customer_support, "~> 0.1"}
```

Then `mix deps.get`. The module appears in the admin Modules page and sidebar automatically via `PhoenixKit.Module` auto-discovery.

## Module integration

The package registers itself with PhoenixKit's module system. No manual router wiring needed — admin routes are auto-discovered at compile time via `route_module/0`.

## Routes

### Admin routes (registered by this package via `route_module/0`)

| Path | LiveView |
|------|----------|
| `/admin/customer-support` | `PhoenixKitCustomerSupport.Web.List` |
| `/admin/customer-support/tickets` | `PhoenixKitCustomerSupport.Web.List` |
| `/admin/customer-support/tickets/new` | `PhoenixKitCustomerSupport.Web.New` |
| `/admin/customer-support/tickets/:uuid` | `PhoenixKitCustomerSupport.Web.Details` |
| `/admin/customer-support/tickets/:uuid/edit` | `PhoenixKitCustomerSupport.Web.Edit` |
| `/admin/settings/customer-support` | `PhoenixKitCustomerSupport.Web.Settings` |

### User dashboard routes (wired by PhoenixKit core via `Code.ensure_loaded?` guards)

| Path | LiveView |
|------|----------|
| `/dashboard/customer-support/tickets` | `PhoenixKitCustomerSupport.Web.UserList` |
| `/dashboard/customer-support/tickets/new` | `PhoenixKitCustomerSupport.Web.UserNew` |
| `/dashboard/customer-support/tickets/:id` | `PhoenixKitCustomerSupport.Web.UserDetails` |

User-facing routes are registered by `PhoenixKitWeb.Integration` in the core library when this package is present — no additional router configuration is required in the host app.

## Settings

The following settings keys control this module's behaviour. They are managed via the admin Settings UI (`/admin/settings/customer-support`) or directly via `PhoenixKit.Settings`.

| Key | Default | Description |
|-----|---------|-------------|
| `customer_support_enabled` | `false` | Enables or disables the customer support module globally. |
| `customer_support_per_page` | `20` | Number of tickets shown per page in admin and user list views. |
| `customer_support_comments_enabled` | `true` | Allows users and agents to post comments on tickets. |
| `customer_support_internal_notes_enabled` | `true` | Enables internal (agent-only) notes on tickets. |
| `customer_support_attachments_enabled` | `true` | Allows file attachments to be added to tickets and comments. |
| `customer_support_allow_reopen` | `true` | Permits closed tickets to be reopened by users or agents. |

## Development

```sh
mix deps.get
mix compile
mix test
```
