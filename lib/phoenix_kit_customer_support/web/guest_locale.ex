defmodule PhoenixKitCustomerSupport.Web.GuestLocale do
  @moduledoc false
  # The public guest pages translate through this module's own backend. Core
  # sets its own backend's locale for the request; mirror it (base language:
  # `et-EE` → `et`) so these pages follow the visitor's language.

  def apply do
    case Gettext.get_locale(PhoenixKitWeb.Gettext) do
      locale when is_binary(locale) and locale != "" ->
        base = locale |> String.split(["-", "_"]) |> hd() |> String.downcase()
        Gettext.put_locale(PhoenixKitCustomerSupport.Gettext, base)
        base

      _ ->
        Gettext.get_locale(PhoenixKitCustomerSupport.Gettext)
    end
  rescue
    _ -> Gettext.get_locale(PhoenixKitCustomerSupport.Gettext)
  end

  @doc false
  # The visitor's address for `RateLimit`. `get_connect_info/2` answers only
  # during `mount/3`, so each page reads it there and keeps it in `:peer_ip`.
  # Core's resolution: the peer, or behind a trusted proxy the forwarded
  # client — never the proxy itself, which would put every visitor in one
  # bucket.
  def peer_ip(socket) do
    PhoenixKit.Utils.IpAddress.client_address_from_socket(socket)
  rescue
    _ -> nil
  end
end
