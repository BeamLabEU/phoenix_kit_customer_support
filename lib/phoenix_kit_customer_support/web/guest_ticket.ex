defmodule PhoenixKitCustomerSupport.Web.GuestTicket do
  @moduledoc """
  A guest's own request (`/support/requests/:token`), reached through the
  signed link `PhoenixKitCustomerSupport.GuestRequests` emails. Opening it
  (the connected LiveView, not the static render a mail scanner prefetches)
  verifies the guest's address. Shows the request and its public comments
  (never internal notes) and takes the guest's replies while the ticket is
  not closed. An expired or invalid link shows a notice with the way to
  get a fresh one.
  """

  use PhoenixKitWeb, :live_view
  use Gettext, backend: PhoenixKitCustomerSupport.Gettext

  alias PhoenixKitCustomerSupport.Events
  alias PhoenixKitCustomerSupport.GuestRequests
  alias PhoenixKitCustomerSupport.Paths
  alias PhoenixKitCustomerSupport.Ticket
  alias PhoenixKitCustomerSupport.Web.GuestLocale
  alias PhoenixKitCustomerSupport.Web.GuestNew

  @impl true
  def mount(_params, _session, socket) do
    GuestLocale.apply()

    {:ok,
     assign(socket,
       page_title: gettext("Your support request"),
       peer_ip: GuestLocale.peer_ip(socket),
       ticket: nil,
       token: nil,
       link_error: nil,
       comments: [],
       error: nil,
       honeypot: GuestRequests.honeypot_field(),
       reply_form: to_form(%{"content" => ""}, as: :reply)
     )}
  end

  @impl true
  def handle_params(%{"token" => token}, uri, socket) do
    socket = assign(socket, :url_path, URI.parse(uri).path)

    socket = assign(socket, :token, token)

    with {:ok, ticket} <- authorized_ticket(token),
         {:ok, ticket} <- maybe_verify(socket, ticket) do
      update_subscription(socket, ticket)

      {:noreply, load(socket, ticket)}
    else
      {:error, reason} -> {:noreply, clear_ticket(socket, reason)}
    end
  end

  @impl true
  def handle_event("reply", %{"reply" => params}, socket) do
    case socket.assigns.ticket do
      %Ticket{} = ticket ->
        case GuestRequests.reply(ticket, params,
               peer_ip: socket.assigns.peer_ip,
               token: socket.assigns.token
             ) do
          {:ok, _comment} ->
            {:noreply,
             socket
             |> refresh()
             |> assign(error: nil, reply_form: to_form(%{"content" => ""}, as: :reply))}

          {:error, %Ecto.Changeset{}} ->
            {:noreply, assign(socket, :error, gettext("Please write a reply first."))}

          # The link no longer speaks for the ticket (expired, or the ticket
          # moved): the page shows the link notice instead.
          {:error, reason} when reason in [:expired, :invalid, :disabled] ->
            {:noreply, clear_ticket(socket, reason)}

          {:error, reason} ->
            {:noreply, socket |> refresh() |> assign(:error, GuestNew.error_message(reason))}
        end

      nil ->
        {:noreply, socket}
    end
  end

  # Any change on the ticket (a staff reply, a status change) reloads it.
  @impl true
  def handle_info(_event, %{assigns: %{ticket: %Ticket{}}} = socket),
    do: {:noreply, refresh(socket)}

  def handle_info(_event, socket), do: {:noreply, socket}

  defp refresh(socket) do
    case authorized_ticket(socket.assigns.token) do
      {:ok, ticket} -> load(socket, ticket)
      {:error, reason} -> clear_ticket(socket, reason)
    end
  end

  defp authorized_ticket(token) do
    if GuestRequests.enabled?(),
      do: GuestRequests.ticket_from_token(token),
      else: {:error, :disabled}
  end

  defp clear_ticket(socket, reason) do
    update_subscription(socket, nil)
    assign(socket, link_error: reason, ticket: nil, comments: [], error: nil)
  end

  defp update_subscription(socket, ticket) do
    previous = socket.assigns.ticket

    if connected?(socket) and (previous && previous.uuid) != (ticket && ticket.uuid) do
      if previous, do: Events.unsubscribe_from_ticket(previous.uuid)
      if ticket, do: Events.subscribe_to_ticket(ticket.uuid)
    end
  end

  # Verified on the connected mount only: mail scanners that prefetch links
  # fetch the static render and rarely run the LiveView socket.
  defp maybe_verify(socket, ticket) do
    if connected?(socket), do: GuestRequests.verify(ticket), else: {:ok, ticket}
  end

  defp load(socket, ticket),
    do:
      assign(socket,
        ticket: ticket,
        link_error: nil,
        comments: GuestRequests.list_comments(ticket)
      )

  defp author(%{user_uuid: nil}, ticket), do: ticket.guest_name
  defp author(_comment, _ticket), do: gettext("Support team")

  defp status_label("open"), do: gettext("Open")
  defp status_label("in_progress"), do: gettext("In Progress")
  defp status_label("resolved"), do: gettext("Resolved")
  defp status_label("closed"), do: gettext("Closed")
  defp status_label(other), do: other

  @impl true
  def render(assigns) do
    ~H"""
    <PhoenixKitWeb.Components.LayoutWrapper.app_layout
      socket={@socket}
      flash={@flash}
      phoenix_kit_current_scope={assigns[:phoenix_kit_current_scope]}
      page_title={@page_title}
      current_path={assigns[:url_path] || "/"}
    >
      <div class="max-w-2xl mx-auto px-4 py-10 space-y-6">
        <div :if={@link_error} id="guest-ticket-link-error" class="alert alert-warning flex-col items-start">
          <span :if={@link_error == :disabled}>
            {gettext("Support requests without an account are not available.")}
          </span>
          <span :if={@link_error == :expired}>{gettext("This link has expired.")}</span>
          <span :if={@link_error not in [:disabled, :expired]}>
            {gettext("This link is invalid.")}
          </span>
          <.link :if={@link_error != :disabled} navigate={Paths.guest_request_path()} class="link">
            {gettext("Get a fresh link by email")}
          </.link>
        </div>

        <div :if={@ticket} id="guest-ticket" class="space-y-6">
          <div>
            <h1 class="text-2xl font-semibold">{@ticket.title}</h1>
            <p class="text-sm text-base-content/60">
              <span id="guest-ticket-status" class="badge badge-ghost">{status_label(@ticket.status)}</span>
            </p>
          </div>

          <div class="card bg-base-100 shadow">
            <div class="card-body">
              <p class="text-sm font-medium">{@ticket.guest_name}</p>
              <p class="whitespace-pre-line">{@ticket.description}</p>
            </div>
          </div>

          <div id="guest-ticket-comments" class="space-y-3">
            <div :for={comment <- @comments} id={"comment-#{comment.uuid}"} class="card bg-base-200">
              <div class="card-body py-4">
                <p class="text-sm font-medium">{author(comment, @ticket)}</p>
                <p class="whitespace-pre-line">{comment.content}</p>
              </div>
            </div>
          </div>

          <div :if={@error} id="guest-ticket-error" class="alert alert-error">{@error}</div>

          <.form
            :if={Ticket.can_comment?(@ticket)}
            for={@reply_form}
            id="guest-reply-form"
            phx-submit="reply"
            class="space-y-3"
          >
            <.textarea field={@reply_form[:content]} label={gettext("Your reply")} rows="4" />
            <div aria-hidden="true" class="sr-only">
              <input type="text" name={"reply[#{@honeypot}]"} value="" tabindex="-1" autocomplete="off" />
            </div>
            <button type="submit" class="btn btn-primary" phx-disable-with={gettext("Sending…")}>
              {gettext("Send reply")}
            </button>
          </.form>

          <p :if={not Ticket.can_comment?(@ticket)} class="text-sm text-base-content/60">
            {gettext("This request is closed and no longer takes replies.")}
          </p>
        </div>
      </div>
    </PhoenixKitWeb.Components.LayoutWrapper.app_layout>
    """
  end
end
