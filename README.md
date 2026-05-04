# PhoenixKitCustomerSupport

Customer service ticketing module for [PhoenixKit](https://github.com/BeamLabEU/phoenix_kit).

Provides a full ticketing system: create tickets, track status, add comments and attachments, manage agents. Extracted from PhoenixKit core (>= 1.7.104).

## Installation

Add to the host app's `mix.exs`:

```elixir
{:phoenix_kit_customer_support, "~> 0.1"}
```

Then `mix deps.get`. The module appears in the admin Modules page and sidebar automatically via `PhoenixKit.Module` auto-discovery.

## Module integration

The package registers itself with PhoenixKit's module system. No manual router wiring needed — routes are auto-discovered at compile time via `route_module/0`.

## Routes

| Path | LiveView |
|------|----------|
| `/admin/customer-support` | `PhoenixKitCustomerSupport.Web.List` |
| `/admin/customer-support/tickets/new` | `PhoenixKitCustomerSupport.Web.New` |
| `/admin/customer-support/tickets/:uuid` | `PhoenixKitCustomerSupport.Web.Details` |
| `/admin/customer-support/tickets/:uuid/edit` | `PhoenixKitCustomerSupport.Web.Edit` |
| `/admin/settings/customer-support` | `PhoenixKitCustomerSupport.Web.Settings` |
| `/dashboard/customer-support/tickets` | `PhoenixKitCustomerSupport.Web.UserList` |

## Development

```sh
mix deps.get
mix compile
mix test
```
