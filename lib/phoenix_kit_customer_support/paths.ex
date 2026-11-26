defmodule PhoenixKitCustomerSupport.Paths do
  @moduledoc """
  Centralized path helpers for the Customer Support module. All paths go through
  `PhoenixKit.Utils.Routes.path/1` for prefix/locale handling.
  """

  alias PhoenixKit.Utils.Routes

  @admin_base "/admin/customer-support"
  @admin_tickets "/admin/customer-support/tickets"
  @settings_base "/admin/settings/customer-support"
  @user_tickets "/dashboard/customer-support/tickets"
  @guest_request "/support/request"
  @guest_tickets "/support/requests"

  def tickets_path, do: Routes.path(@admin_tickets)
  def new_ticket_path, do: Routes.path("#{@admin_tickets}/new")
  def ticket_path(id), do: Routes.path("#{@admin_tickets}/#{id}")
  def edit_ticket_path(id), do: Routes.path("#{@admin_tickets}/#{id}/edit")
  def settings_path, do: Routes.path(@settings_base)
  def admin_path, do: Routes.path(@admin_base)
  def user_tickets_path, do: Routes.path(@user_tickets)
  def user_new_ticket_path, do: Routes.path("#{@user_tickets}/new")
  def user_ticket_path(id), do: Routes.path("#{@user_tickets}/#{id}")

  @doc "Public guest request form (`allow_anonymous_requests`)."
  def guest_request_path, do: Routes.path(@guest_request)

  @doc "A guest's request page, reached through its signed token."
  def guest_ticket_path(token), do: Routes.path("#{@guest_tickets}/#{token}")

  @doc "Absolute URL of a guest's request page (for emails)."
  def guest_ticket_url(token), do: Routes.url("#{@guest_tickets}/#{token}")
end
