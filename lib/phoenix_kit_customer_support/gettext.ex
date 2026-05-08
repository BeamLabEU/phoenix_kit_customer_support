defmodule PhoenixKitCustomerSupport.Gettext do
  @moduledoc """
  Gettext backend for `phoenix_kit_customer_support`.

  Owns the translation catalogues under `priv/gettext/`. Locale is set
  per-request by the parent application; this module is only responsible
  for looking msgids up against the active locale.

  See `guides/per-module-i18n.md` in the `phoenix_kit` core guides for
  the full setup and conventions.
  """
  use Gettext.Backend, otp_app: :phoenix_kit_customer_support
end
