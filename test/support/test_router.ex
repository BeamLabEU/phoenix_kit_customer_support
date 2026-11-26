defmodule PhoenixKitCustomerSupport.Test.Router do
  @moduledoc """
  Minimal router for the guest-page tests: the two public paths
  `PhoenixKitCustomerSupport.Paths` builds (bare — the test helper pins the
  URL prefix to `"/"` and never enables Languages). What `Routes.generate/1`
  emits into a host is pinned separately in `routes_test.exs`.
  """

  use Phoenix.Router

  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, {PhoenixKitCustomerSupport.Test.Layouts, :root})
    plug(:protect_from_forgery)
  end

  scope "/", PhoenixKitCustomerSupport.Web do
    pipe_through(:browser)

    live_session :customer_support_public_test,
      layout: {PhoenixKitCustomerSupport.Test.Layouts, :app} do
      live("/support/request", GuestNew, :new, as: :guest_new)
      live("/support/requests/:token", GuestTicket, :show, as: :guest_ticket)
    end
  end
end
