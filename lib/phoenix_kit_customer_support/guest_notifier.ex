defmodule PhoenixKitCustomerSupport.GuestNotifier do
  @moduledoc """
  Emails to guest requesters (`PhoenixKitCustomerSupport.GuestRequests`),
  sent through core's `PhoenixKit.Mailer` (Integrations → host mailer →
  built-in; honours the blocklist). Plain text, in the locale the guest
  used when filing (`metadata["guest_locale"]`). Every send is best-effort:
  a mail failure never fails the request or the reply, it is logged.

  Bodies carry no ticket content beyond the title the guest typed, so a
  forwarded or misdirected mail exposes nothing a staff member wrote.
  """

  use Gettext, backend: PhoenixKitCustomerSupport.Gettext

  require Logger

  alias PhoenixKitCustomerSupport.Ticket

  @doc "Sent right after filing: confirms the request and verifies the address."
  def request_received(%Ticket{} = ticket, url) do
    with_locale(ticket, fn ->
      deliver(
        ticket.guest_email,
        gettext("Your support request: %{title}", title: ticket.title),
        greeting(ticket) <>
          "\n\n" <>
          gettext(
            "We received your request. Open the link below to confirm your email address, follow the request and reply to it:"
          ) <>
          "\n\n" <>
          url <>
          "\n\n" <>
          expiry_line() <>
          "\n\n" <>
          gettext("If you did not send this request, you can ignore this email.")
      )
    end)
  end

  @doc "Sent when staff reply publicly on a guest request."
  def reply_posted(%Ticket{} = ticket, url) do
    with_locale(ticket, fn ->
      deliver(
        ticket.guest_email,
        gettext("New reply to your support request: %{title}", title: ticket.title),
        greeting(ticket) <>
          "\n\n" <>
          gettext("There is a new reply to your request. Read it and answer here:") <>
          "\n\n" <> url <> "\n\n" <> expiry_line()
      )
    end)
  end

  @doc "Sent on request: fresh links to every open request of an address."
  def links(email, [{%Ticket{} = first, _url} | _] = tickets_with_urls) do
    with_locale(first, fn ->
      lines =
        Enum.map_join(tickets_with_urls, "\n\n", fn {ticket, url} ->
          ticket.title <> "\n" <> url
        end)

      deliver(
        email,
        gettext("Links to your support requests"),
        gettext("Here are the links to your open support requests:") <>
          "\n\n" <>
          lines <>
          "\n\n" <>
          expiry_line() <>
          "\n\n" <> gettext("If you did not ask for these links, you can ignore this email.")
      )
    end)
  end

  defp greeting(%Ticket{guest_name: name}) when is_binary(name) and name != "",
    do: gettext("Hello %{name},", name: name)

  defp greeting(_), do: gettext("Hello,")

  defp expiry_line do
    days = max(div(PhoenixKitCustomerSupport.GuestRequests.link_max_age(), 86_400), 1)

    ngettext(
      "The link is valid for %{count} day. Each new reply sends you a fresh one.",
      "The link is valid for %{count} days. Each new reply sends you a fresh one.",
      days
    )
  end

  defp with_locale(%Ticket{metadata: %{"guest_locale" => locale}}, fun)
       when is_binary(locale) and locale != "" do
    Gettext.with_locale(PhoenixKitCustomerSupport.Gettext, locale, fun)
  end

  defp with_locale(_ticket, fun), do: fun.()

  defp deliver(to, subject, body) do
    from_email = PhoenixKit.Settings.get_setting("from_email", "noreply@localhost")
    from_name = PhoenixKit.Settings.get_setting("from_name", "Support")

    email =
      Swoosh.Email.new()
      |> Swoosh.Email.to(to)
      |> Swoosh.Email.from({from_name, from_email})
      |> Swoosh.Email.subject(subject)
      |> Swoosh.Email.text_body(body)

    case PhoenixKit.Mailer.deliver_email(email) do
      {:ok, _} -> :ok
      {:error, reason} -> log_failure(subject, reason)
    end
  rescue
    e -> log_failure(subject, e)
  catch
    :exit, reason -> log_failure(subject, reason)
  end

  # The address is PII: never logged.
  defp log_failure(subject, reason) do
    Logger.warning("[CustomerSupport] guest email #{inspect(subject)} failed: #{inspect(reason)}")
    :error
  end
end
