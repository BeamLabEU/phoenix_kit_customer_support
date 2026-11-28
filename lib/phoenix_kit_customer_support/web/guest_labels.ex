defmodule PhoenixKitCustomerSupport.Web.GuestLabels do
  @moduledoc false
  # Guest-request labels for the admin ticket pages, translated through
  # this module's backend (those templates otherwise use core's).
  use Gettext, backend: PhoenixKitCustomerSupport.Gettext

  def guest, do: gettext("Guest")
  def guest_no_account, do: gettext("Guest (no account)")
  def email_confirmed, do: gettext("email confirmed")
  def email_not_confirmed, do: gettext("email not confirmed")
end
