# Built with Module.create/3 so the AST from `generate/1` is spliced into a
# block that already carries `use Phoenix.Router` (the bookings pattern).
host_router_body = fn prefix ->
  quote do
    use Phoenix.Router, helpers: false

    import Phoenix.LiveView.Router

    pipeline :browser do
      plug(:accepts, ["html"])
    end

    pipeline :phoenix_kit_auto_setup do
      plug(:accepts, ["html"])
    end

    pipeline :phoenix_kit_locale_validation do
      plug(:accepts, ["html"])
    end

    unquote(PhoenixKitCustomerSupport.Routes.generate(prefix))
  end
end

Module.create(
  PhoenixKitCustomerSupport.Web.RoutesTest.HostRouter,
  host_router_body.("/phoenix_kit"),
  Macro.Env.location(__ENV__)
)

defmodule PhoenixKitCustomerSupport.Web.RoutesTest do
  @moduledoc "Pins the public guest paths `Routes.generate/1` emits into a host router."
  use ExUnit.Case, async: true

  alias PhoenixKitCustomerSupport.Web.{GuestNew, GuestTicket}
  alias PhoenixKitCustomerSupport.Web.RoutesTest.HostRouter

  defp route(path), do: Phoenix.Router.route_info(HostRouter, "GET", path, "localhost")

  test "both pages are routed bare and under a locale" do
    for path <- ["/phoenix_kit/support/request", "/phoenix_kit/et/support/request"] do
      assert %{phoenix_live_view: {GuestNew, :new, _, _}} = route(path)
    end

    for path <- ["/phoenix_kit/support/requests/abc", "/phoenix_kit/ru/support/requests/abc"] do
      assert %{phoenix_live_view: {GuestTicket, :show, _, _}} = route(path)
    end
  end

  test "nothing else is routed (no catch-all)" do
    assert route("/phoenix_kit/admin/customer-support") == :error
    assert route("/phoenix_kit/support") == :error
  end
end
