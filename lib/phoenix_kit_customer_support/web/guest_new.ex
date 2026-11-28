defmodule PhoenixKitCustomerSupport.Web.GuestNew do
  @moduledoc """
  Public form for an anonymous support request (`/support/request`), live
  only while `customer_support_allow_anonymous_requests` is on. See
  `PhoenixKitCustomerSupport.GuestRequests` for the flow and spam controls.
  """

  use PhoenixKitWeb, :live_view
  use Gettext, backend: PhoenixKitCustomerSupport.Gettext

  alias PhoenixKitCustomerSupport.GuestRequests
  alias PhoenixKitCustomerSupport.Web.GuestLocale

  @impl true
  def mount(_params, _session, socket) do
    locale = GuestLocale.apply()

    {:ok,
     socket
     |> assign(
       page_title: gettext("Contact support"),
       locale: locale,
       peer_ip: GuestLocale.peer_ip(socket),
       enabled: GuestRequests.enabled?(),
       submitted: false,
       resent: false,
       error: nil,
       honeypot: GuestRequests.honeypot_field()
     )
     |> assign_form(GuestRequests.change_request())
     |> assign(:resend_form, to_form(%{"email" => ""}, as: :resend))}
  end

  @impl true
  def handle_params(_params, uri, socket) do
    {:noreply, assign(socket, :url_path, URI.parse(uri).path)}
  end

  @impl true
  def handle_event("validate", %{"request" => params}, socket) do
    changeset = params |> GuestRequests.change_request() |> Map.put(:action, :validate)
    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("submit", %{"request" => params}, socket) do
    case GuestRequests.submit(params,
           peer_ip: socket.assigns.peer_ip,
           locale: socket.assigns.locale
         ) do
      {:ok, _ticket_or_discarded} ->
        {:noreply, assign(socket, submitted: true, error: nil)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  def handle_event("resend", %{"resend" => %{"email" => email} = params}, socket) do
    case GuestRequests.resend_links(email, peer_ip: socket.assigns.peer_ip, params: params) do
      :ok -> {:noreply, assign(socket, resent: true, error: nil)}
      {:error, reason} -> {:noreply, assign(socket, :error, error_message(reason))}
    end
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset, as: :request))

  @doc false
  def error_message(:rate_limited),
    do: gettext("Too many attempts. Please wait a while and try again.")

  def error_message(:disabled),
    do: gettext("Support requests without an account are not available.")

  def error_message(:closed), do: gettext("This request is closed and no longer takes replies.")
  def error_message(_), do: gettext("Your request could not be sent. Please try again later.")

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
      <div class="max-w-xl mx-auto px-4 py-10 space-y-6">
        <h1 class="text-2xl font-semibold">{gettext("Contact support")}</h1>

        <div :if={not @enabled} id="guest-request-disabled" class="alert alert-warning">
          {gettext("Support requests without an account are not available.")}
        </div>

        <div :if={@error} id="guest-request-error" class="alert alert-error">{@error}</div>

        <div :if={@enabled and @submitted} id="guest-request-sent" class="alert alert-success">
          {gettext(
            "Thank you. We have sent you an email with a link to your request. Open it to confirm your address; then you can follow the request and reply."
          )}
        </div>

        <.form
          :if={@enabled and not @submitted}
          for={@form}
          id="guest-request-form"
          phx-change="validate"
          phx-submit="submit"
          class="space-y-4"
        >
          <.input field={@form[:guest_name]} type="text" label={gettext("Your name")} required />
          <.input field={@form[:guest_email]} type="email" label={gettext("Your email")} required />
          <.input field={@form[:title]} type="text" label={gettext("Subject")} required />
          <.textarea
            field={@form[:description]}
            label={gettext("How can we help?")}
            rows="6"
            required
          />
          <%!-- Honeypot: off-screen, out of the tab order and hidden from
             assistive tech. People never fill it; form-filling bots do. --%>
          <div aria-hidden="true" class="sr-only">
            <label for={"request_#{@honeypot}"}>{gettext("Leave this field empty")}</label>
            <input
              type="text"
              id={"request_#{@honeypot}"}
              name={"request[#{@honeypot}]"}
              value=""
              tabindex="-1"
              autocomplete="off"
            />
          </div>
          <button type="submit" class="btn btn-primary" phx-disable-with={gettext("Sending…")}>
            {gettext("Send request")}
          </button>
        </.form>

        <div :if={@enabled} class="card bg-base-200">
          <div class="card-body gap-3">
            <h2 class="card-title text-base">{gettext("Lost your link?")}</h2>
            <p :if={@resent} id="guest-resend-sent" class="text-sm">
              {gettext("If we have open requests for that address, we have emailed fresh links to it.")}
            </p>
            <.form
              :if={not @resent}
              for={@resend_form}
              id="guest-resend-form"
              phx-submit="resend"
              class="flex flex-col sm:flex-row gap-2"
            >
              <input
                type="email"
                name="resend[email]"
                class="input w-full"
                placeholder={gettext("Your email")}
                aria-label={gettext("Your email")}
                required
              />
              <div aria-hidden="true" class="sr-only">
                <input type="text" name={"resend[#{@honeypot}]"} value="" tabindex="-1" autocomplete="off" />
              </div>
              <button type="submit" class="btn">{gettext("Email me my links")}</button>
            </.form>
          </div>
        </div>

      </div>
    </PhoenixKitWeb.Components.LayoutWrapper.app_layout>
    """
  end
end
