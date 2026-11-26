defmodule PhoenixKitCustomerSupport.RateLimit do
  @moduledoc """
  A ceiling on what an anonymous visitor can make this module do and send.

  A guest request mails the address it was given, so an open form is a way
  to mail a stranger and to fill the queue. `check/3` counts one attempt
  against the email address and against the peer address, per hour, on
  core's rate limiter (`PhoenixKit.Users.RateLimiter.Backend`).

  The peer comes from LiveView's `:peer_data`, so it needs
  `connect_info: [:peer_data, session: ...]` on the host's socket; without
  it only the address bucket applies. Behind a proxy the host resolves the
  real address before Phoenix (`RemoteIp`): forwarded headers are never read
  here. A limiter that is not running allows the attempt (and logs).

  Limits, per hour:

      config :phoenix_kit_customer_support, :guest_rate_limit,
        per_address: 5,
        per_peer: 20
  """

  require Logger

  alias PhoenixKit.Users.RateLimiter.Backend, as: Limiter

  @hour_ms 60 * 60 * 1000
  @defaults [per_address: 5, per_peer: 20]

  @doc """
  Counts one attempt of `action` (`:request`, `:reply`, `:resend`).
  `:ok`, or `{:error, :rate_limited}` once a bucket is over its limit.
  """
  @spec check(atom(), String.t() | nil, :inet.ip_address() | nil) ::
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
      :ok
  catch
    :exit, reason ->
      Logger.warning("[CustomerSupport] rate limiter unavailable: #{inspect(reason)}")
      :ok
  end

  defp configured_limits,
    do: Application.get_env(:phoenix_kit_customer_support, :guest_rate_limit, [])

  defp address_bucket(action, email, limits) when is_binary(email) and email != "" do
    {"customer_support:#{action}:address:#{email |> String.trim() |> String.downcase()}",
     limits[:per_address]}
  end

  defp address_bucket(_action, _email, _limits), do: nil

  defp peer_bucket(_action, nil, _limits), do: nil

  defp peer_bucket(action, ip, limits),
    do: {"customer_support:#{action}:peer:#{ip_bucket(ip)}", limits[:per_peer]}

  # IPv6 by its /64: one subscriber holds a whole prefix.
  defp ip_bucket({a, b, c, d, _, _, _, _}), do: Enum.join([a, b, c, d], ":") <> "::/64"
  defp ip_bucket(ip), do: ip |> :inet.ntoa() |> to_string()
end
