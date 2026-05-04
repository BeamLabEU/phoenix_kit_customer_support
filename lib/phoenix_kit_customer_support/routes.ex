defmodule PhoenixKitCustomerSupport.Routes do
  @moduledoc """
  Route declarations for the Customer Support module.
  """

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
