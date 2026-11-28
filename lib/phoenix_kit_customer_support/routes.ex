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

    # One keyword list, escaped whole: live_session/3 takes its options as a
    # single argument (a splice would make them extra arguments).
    opts =
      csp_session() ++
        [
          on_mount:
            extra_on_mount ++ [{PhoenixKitWeb.Users.Auth, :phoenix_kit_mount_current_scope}]
        ]

    quote do
      live_session :phoenix_kit_customer_support_public, unquote(Macro.escape(opts)) do
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
  # The page's CSP nonces in the LiveView session, as core's own live
  # sessions carry them (`PhoenixKitWeb.CSP.live_session/1`; the views'
  # `on_mount` restores them), so a `<style>` patched in after the socket
  # connects still gets the nonce. Feature-detected: a core release without
  # `PhoenixKitWeb.CSP` gets no `session:` and nothing else changes.
  def csp_session do
    if Code.ensure_loaded?(PhoenixKitWeb.CSP) and
         function_exported?(PhoenixKitWeb.CSP, :live_session, 1),
       do: [session: {PhoenixKitWeb.CSP, :live_session, []}],
       else: []
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
