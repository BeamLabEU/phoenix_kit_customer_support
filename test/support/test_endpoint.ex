defmodule PhoenixKitCustomerSupport.Test.Endpoint do
  @moduledoc """
  Minimal endpoint for the guest-page LiveView tests and for
  `Phoenix.Token` (guest links). The module is a library; in production the
  host's endpoint signs and serves.
  """

  use Phoenix.Endpoint, otp_app: :phoenix_kit_customer_support

  @session_options [
    store: :cookie,
    key: "_phoenix_kit_customer_support_test_key",
    signing_salt: "customer-support-test-salt",
    same_site: "Lax"
  ]

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])

  plug(Plug.Session, @session_options)
  plug(PhoenixKitCustomerSupport.Test.Router)
end
