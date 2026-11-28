defmodule PhoenixKitCustomerSupport.RateLimit do
  @moduledoc """
  A ceiling on what an anonymous visitor can make this module do and send.

  A guest request mails the address it was given, so an open form is a way
  to mail a stranger and to fill the queue. `check/3` counts one attempt
  against the email address and against the peer address, per hour, on
  core's rate limiter (`PhoenixKit.Users.RateLimiter.Backend`).

  The peer is core's `PhoenixKit.Utils.IpAddress.client_address_from_socket/1`
  (`:peer_data`, and behind a trusted proxy its forwarded header from
  `:x_headers`), so it needs `connect_info: [:peer_data, :x_headers,
  session: ...]` on the host's socket; without it only the address bucket
  applies. A limiter that is not running refuses the attempt (and logs).

  Limits, per hour:

      config :phoenix_kit_customer_support, :guest_rate_limit,
        per_address: 5,
        per_peer: 20
  """

  require Logger

  alias PhoenixKit.Users.RateLimiter.Backend, as: Limiter
  alias PhoenixKit.Utils.IpAddress

  @hour_ms 60 * 60 * 1000
  @defaults [per_address: 5, per_peer: 20]

  @doc """
  Counts one attempt of `action` (`:request`, `:reply`, `:resend`).
  `:ok`, or `{:error, :rate_limited}` once a bucket is over its limit.
  """
  @spec check(atom(), String.t() | nil, String.t() | :inet.ip_address() | nil) ::
          :ok | {:error, :rate_limited}
  def check(action, email, peer_ip) do
    limits = Keyword.merge(@defaults, configured_limits())

    [address_bucket(action, email, limits), peer_bucket(action, peer_ip, limits)]
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce_while(:ok, fn {key, limit}, :ok ->
      case Limiter.hit(key, @hour_ms, limit) do
        {:allow, _count} -> {:cont, :ok}
        _denied -> {:halt, {:error, :rate_limited}}
      end
    end)
  rescue
    e ->
      Logger.warning("[CustomerSupport] rate limiter unavailable: #{Exception.message(e)}")
      {:error, :rate_limited}
  catch
    :exit, reason ->
      Logger.warning("[CustomerSupport] rate limiter unavailable: #{inspect(reason)}")
      {:error, :rate_limited}
  end

  defp configured_limits,
    do: Application.get_env(:phoenix_kit_customer_support, :guest_rate_limit, [])

  defp address_bucket(action, email, limits) when is_binary(email) and email != "" do
    {"customer_support:#{action}:address:#{email |> String.trim() |> String.downcase()}",
     limits[:per_address]}
  end

  defp address_bucket(_action, _email, _limits), do: nil

  defp peer_bucket(action, ip, limits) do
    case ip_bucket(ip) do
      nil -> nil
      network -> {"customer_support:#{action}:peer:#{network}", limits[:per_peer]}
    end
  end

  # Core's notion of a visitor's network (`IpAddress.network/1`): an IPv4
  # address (also when it arrives IPv4-mapped on an IPv6 listener) is its
  # own bucket, an IPv6 address its /64.
  defp ip_bucket(nil), do: nil
  defp ip_bucket(ip) when is_tuple(ip), do: ip |> :inet.ntoa() |> to_string() |> ip_bucket()
  defp ip_bucket(ip) when is_binary(ip), do: IpAddress.network(ip)
  defp ip_bucket(_), do: nil
end
