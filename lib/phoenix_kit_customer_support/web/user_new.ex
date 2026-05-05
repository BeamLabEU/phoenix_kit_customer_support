defmodule PhoenixKitCustomerSupport.Web.UserNew do
  @moduledoc """
  LiveView for creating new support tickets with file attachments.

  Users can create tickets with title, description and drag-and-drop file uploads.
  Files are stored via Storage module and attached to the ticket after creation.
  """
  use PhoenixKitWeb, :live_view

  alias PhoenixKit.Settings
  alias PhoenixKit.Utils.Routes
  alias PhoenixKitCustomerSupport
  alias PhoenixKitCustomerSupport.Ticket
  alias PhoenixKitCustomerSupport.Uploads

  @impl true
  def mount(_params, _session, socket) do
    if PhoenixKitCustomerSupport.enabled?() do
      current_user = socket.assigns[:phoenix_kit_current_user]
      ticket = %Ticket{user_uuid: current_user.uuid}
      changeset = Ticket.changeset(ticket, %{})

      attachments_enabled =
        Settings.get_boolean_setting("customer_support_attachments_enabled", true)

      socket =
        socket
        |> assign(:page_title, gettext("New Ticket"))
        |> assign(:current_user, current_user)
        |> assign(:ticket, ticket)
        |> assign(:form, to_form(changeset))
        |> assign(:pending_file_uuids, [])
        |> assign(:pending_files, [])
        |> assign(:attachments_enabled, attachments_enabled)
        |> assign(:upload_errors, [])
        |> maybe_allow_upload(attachments_enabled)

      {:ok, socket}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("Tickets module is not enabled"))
       |> push_navigate(to: Routes.path("/dashboard"))}
    end
  end

  defp maybe_allow_upload(socket, true) do
    allow_upload(socket, :attachments,
      accept: ~w(.jpg .jpeg .png .gif .webp .pdf .doc .docx .txt),
      max_entries: 5,
      max_file_size: 10_000_000,
      auto_upload: true,
      progress: &handle_upload_progress/3
    )
  end

  defp maybe_allow_upload(socket, false), do: socket

  defp handle_upload_progress(:attachments, entry, socket) do
    if entry.done? do
      {:noreply, consume_done_entry(socket, entry)}
    else
      {:noreply, socket}
    end
  end

  defp consume_done_entry(socket, entry) do
    case Uploads.consume_entry(socket, entry, socket.assigns.current_user, "Ticket") do
      {:ok, file} ->
        socket
        |> assign(:pending_file_uuids, socket.assigns.pending_file_uuids ++ [file.uuid])
        |> assign(:pending_files, socket.assigns.pending_files ++ [file])

      {:error, name} ->
        assign(
          socket,
          :upload_errors,
          socket.assigns.upload_errors ++
            [gettext("Failed to store \"%{name}\". Please try again.", name: name)]
        )
    end
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("validate", %{"ticket" => params}, socket) do
    changeset =
      socket.assigns.ticket
      |> Ticket.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("validate", _params, socket) do
    # Handle file upload validation (when only files change)
    {:noreply, socket}
  end

  @impl true
  def handle_event("save", %{"ticket" => params}, socket) do
    current_user = socket.assigns.current_user

    # Files are already consumed via the progress callback; clear errored
    # entries so they don't linger in the upload UI on next render.
    socket = maybe_cancel_errored(socket)
    pending_file_uuids = socket.assigns.pending_file_uuids

    case PhoenixKitCustomerSupport.create_ticket(current_user.uuid, params) do
      {:ok, ticket} ->
        # Attach pending files to the newly created ticket
        Enum.each(pending_file_uuids, fn file_uuid ->
          PhoenixKitCustomerSupport.add_attachment_to_ticket(ticket.uuid, file_uuid)
        end)

        {:noreply,
         socket
         |> put_flash(:info, gettext("Ticket created successfully"))
         |> push_navigate(to: Routes.path("/dashboard/customer-support/tickets/#{ticket.uuid}"))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :attachments, ref)}
  end

  @impl true
  def handle_event("remove_pending_file", %{"uuid" => file_uuid}, socket) do
    pending_file_uuids = Enum.reject(socket.assigns.pending_file_uuids, &(&1 == file_uuid))
    pending_files = Enum.reject(socket.assigns.pending_files, &(&1.uuid == file_uuid))

    {:noreply,
     socket
     |> assign(:pending_file_uuids, pending_file_uuids)
     |> assign(:pending_files, pending_files)}
  end

  defp maybe_cancel_errored(socket) do
    if socket.assigns.attachments_enabled and Map.has_key?(socket.assigns, :uploads) do
      Uploads.cancel_errored_entries(socket, :attachments)
    else
      socket
    end
  end
end
