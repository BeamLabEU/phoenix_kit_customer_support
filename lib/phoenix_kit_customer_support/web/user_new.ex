defmodule PhoenixKitCustomerSupport.Web.UserNew do
  @moduledoc """
  LiveView for creating new support tickets with file attachments.

  Users can create tickets with title, description and drag-and-drop file uploads.
  Files are stored via Storage module and attached to the ticket after creation.
  """
  use PhoenixKitWeb, :live_view

  require Logger

  alias PhoenixKit.Modules.Storage
  alias PhoenixKit.Settings
  alias PhoenixKit.Users.Auth
  alias PhoenixKit.Utils.Routes
  alias PhoenixKitCustomerSupport
  alias PhoenixKitCustomerSupport.Ticket

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
    current_user = socket.assigns.current_user

    result =
      consume_uploaded_entry(socket, entry, fn %{path: path} ->
        ext = Path.extname(entry.client_name) |> String.replace_leading(".", "")
        file_hash = Auth.calculate_file_hash(path)

        case Storage.store_file_in_buckets(
               path,
               PhoenixKitCustomerSupport.Uploads.file_type_from_mime(entry.client_type),
               current_user.uuid,
               file_hash,
               ext,
               entry.client_name
             ) do
          {:ok, file, :duplicate} ->
            Logger.info("Ticket attachment is duplicate with ID: #{file.uuid}")
            {:ok, file}

          {:ok, file} ->
            Logger.info("Ticket attachment stored with ID: #{file.uuid}")
            {:ok, file}

          {:error, reason} ->
            Logger.error("Storage Error: #{inspect(reason)}")
            {:ok, nil}
        end
      end)

    case result do
      %{} = file ->
        socket
        |> assign(:pending_file_uuids, socket.assigns.pending_file_uuids ++ [file.uuid])
        |> assign(:pending_files, socket.assigns.pending_files ++ [file])

      _ ->
        socket
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

    # First, process any pending uploads
    socket = process_pending_uploads(socket)
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

  defp process_pending_uploads(socket) do
    if socket.assigns.attachments_enabled and
         Map.has_key?(socket.assigns, :uploads) and
         socket.assigns.uploads.attachments.entries != [] do
      socket
      |> cancel_errored_entries(:attachments)
      |> do_process_uploads()
    else
      socket
    end
  end

  defp cancel_errored_entries(socket, name) do
    upload = Map.get(socket.assigns.uploads, name)

    refs =
      Enum.uniq(
        Enum.map(upload.errors, fn {ref, _} -> ref end) ++
          for(entry <- upload.entries, not entry.valid?, do: entry.ref)
      )

    Enum.reduce(refs, socket, &cancel_upload(&2, name, &1))
  end

  defp do_process_uploads(socket) do
    current_user = socket.assigns.current_user

    uploaded_files =
      consume_uploaded_entries(socket, :attachments, fn %{path: path}, entry ->
        ext = Path.extname(entry.client_name) |> String.replace_leading(".", "")
        user_uuid = current_user.uuid

        {:ok, _stat} = File.stat(path)
        file_hash = Auth.calculate_file_hash(path)

        case Storage.store_file_in_buckets(
               path,
               PhoenixKitCustomerSupport.Uploads.file_type_from_mime(entry.client_type),
               user_uuid,
               file_hash,
               ext,
               entry.client_name
             ) do
          {:ok, file, :duplicate} ->
            Logger.info("Ticket attachment is duplicate with ID: #{file.uuid}")
            {:ok, file}

          {:ok, file} ->
            Logger.info("Ticket attachment stored with ID: #{file.uuid}")
            {:ok, file}

          {:error, reason} ->
            Logger.error("Storage Error: #{inspect(reason)}")
            {:ok, nil}
        end
      end)

    new_files = Enum.reject(uploaded_files, &is_nil/1)
    new_file_uuids = Enum.map(new_files, & &1.uuid)

    socket
    |> assign(:pending_file_uuids, socket.assigns.pending_file_uuids ++ new_file_uuids)
    |> assign(:pending_files, socket.assigns.pending_files ++ new_files)
  end
end
