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

  def tickets_path, do: Routes.path(@admin_tickets)
  def new_ticket_path, do: Routes.path("#{@admin_tickets}/new")
  def ticket_path(id), do: Routes.path("#{@admin_tickets}/#{id}")
  def edit_ticket_path(id), do: Routes.path("#{@admin_tickets}/#{id}/edit")
  def settings_path, do: Routes.path(@settings_base)
  def admin_path, do: Routes.path(@admin_base)
  def user_tickets_path, do: Routes.path(@user_tickets)
  def user_new_ticket_path, do: Routes.path("#{@user_tickets}/new")
  def user_ticket_path(id), do: Routes.path("#{@user_tickets}/#{id}")
end
