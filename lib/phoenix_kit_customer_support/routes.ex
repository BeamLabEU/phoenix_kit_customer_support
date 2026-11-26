defmodule PhoenixKitCustomerSupport.Routes do
  @moduledoc """
  Route declarations for the Customer Support module.

  Admin pages come from `admin_routes/0` / `admin_locale_routes/0`. The
  public guest pages (`/support/request`, `/support/requests/:token`) come
  from `generate/1`, which core splices into the host router ahead of its
  public surface. They are always routed; whether they accept anything is
  the runtime setting `customer_support_allow_anonymous_requests` (default
  off — the pages then answer "not available"). Both a bare and a
  `/:locale` shape are emitted in one `live_session`, as
  `PhoenixKitBookings.Web.Routes` does, so links built through
  `PhoenixKit.Utils.Routes.path/1` resolve when Languages is on. The paths
  are literal (no catch-all), so they cannot bind an admin URL.
  """

  @doc false
  def generate(url_prefix) do
    extra_on_mount = Application.get_env(:phoenix_kit, :extra_live_session_on_mount, [])

    quote do
      live_session :phoenix_kit_customer_support_public,
        on_mount:
          unquote(
            extra_on_mount ++
              [{PhoenixKitWeb.Users.Auth, :phoenix_kit_mount_current_scope}]
          ) do
        scope unquote(localized_scope(url_prefix)) do
          pipe_through([:browser, :phoenix_kit_auto_setup, :phoenix_kit_locale_validation])
          unquote(public_live_routes())
        end

        scope unquote(url_prefix) do
          pipe_through([:browser, :phoenix_kit_auto_setup, :phoenix_kit_locale_validation])
          unquote(public_live_routes())
        end
      end
    end
  end

  @doc false
  def public_routes(_url_prefix), do: nil

  defp localized_scope(prefix) when prefix in ["/", ""], do: "/:locale"
  defp localized_scope(prefix), do: "#{prefix}/:locale"

  defp public_live_routes do
    quote do
      live "/support/request", PhoenixKitCustomerSupport.Web.GuestNew, :new,
        as: :customer_support_guest_new

      live "/support/requests/:token", PhoenixKitCustomerSupport.Web.GuestTicket, :show,
        as: :customer_support_guest_ticket
    end
  end

  def admin_locale_routes do
    quote do
      live "/admin/customer-support",
           PhoenixKitCustomerSupport.Web.List,
           :index,
           as: :customer_support_index_localized

      live "/admin/customer-support/tickets",
           PhoenixKitCustomerSupport.Web.List,
           :index,
           as: :customer_support_list_localized

      live "/admin/customer-support/tickets/new",
           PhoenixKitCustomerSupport.Web.New,
           :new,
           as: :customer_support_new_localized

      live "/admin/customer-support/tickets/:id",
           PhoenixKitCustomerSupport.Web.Details,
           :show,
           as: :customer_support_details_localized

      live "/admin/customer-support/tickets/:id/edit",
           PhoenixKitCustomerSupport.Web.Edit,
           :edit,
           as: :customer_support_edit_localized

      live "/admin/settings/customer-support",
           PhoenixKitCustomerSupport.Web.Settings,
           :index,
           as: :customer_support_settings_localized
    end
  end

  def admin_routes do
    quote do
      live "/admin/customer-support",
           PhoenixKitCustomerSupport.Web.List,
           :index,
           as: :customer_support_index

      live "/admin/customer-support/tickets",
           PhoenixKitCustomerSupport.Web.List,
           :index,
           as: :customer_support_list

      live "/admin/customer-support/tickets/new",
           PhoenixKitCustomerSupport.Web.New,
           :new,
           as: :customer_support_new

      live "/admin/customer-support/tickets/:id",
           PhoenixKitCustomerSupport.Web.Details,
           :show,
           as: :customer_support_details

      live "/admin/customer-support/tickets/:id/edit",
           PhoenixKitCustomerSupport.Web.Edit,
           :edit,
           as: :customer_support_edit

      live "/admin/settings/customer-support",
           PhoenixKitCustomerSupport.Web.Settings,
           :index,
           as: :customer_support_settings
    end
  end
end
