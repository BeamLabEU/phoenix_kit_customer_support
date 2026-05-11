defmodule PhoenixKitCustomerSupport.Web.Settings do
  @moduledoc """
  LiveView for configuring the Tickets module settings.
  """

  use PhoenixKitWeb, :live_view
  use Gettext, backend: PhoenixKitCustomerSupport.Gettext

  alias PhoenixKit.Settings
  alias PhoenixKitCustomerSupport

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns[:phoenix_kit_current_user]

    socket =
      socket
      |> assign(:page_title, "Customer Support Settings")
      |> assign(:current_user, current_user)
      |> load_settings()

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_internal_notes", _params, socket) do
    toggle_boolean_setting(
      socket,
      "customer_support_internal_notes_enabled",
      :internal_notes_enabled,
      "Internal notes"
    )
  end

  @impl true
  def handle_event("toggle_attachments", _params, socket) do
    toggle_boolean_setting(
      socket,
      "customer_support_attachments_enabled",
      :attachments_enabled,
      "Attachments"
    )
  end

  @impl true
  def handle_event("toggle_allow_reopen", _params, socket) do
    toggle_boolean_setting(socket, "customer_support_allow_reopen", :allow_reopen, "Allow reopen")
  end

  @impl true
  def handle_event("update_per_page", %{"per_page" => value}, socket) do
    case Settings.update_setting("customer_support_per_page", value) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Per page setting updated")
         |> assign(:per_page, String.to_integer(value))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update setting")}
    end
  end

  defp toggle_boolean_setting(socket, key, assign_key, label) do
    current_value = Map.get(socket.assigns, assign_key)
    new_value = !current_value

    case Settings.update_setting(key, to_string(new_value)) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{label} #{if new_value, do: "enabled", else: "disabled"}")
         |> assign(assign_key, new_value)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update setting")}
    end
  end

  defp load_settings(socket) do
    socket
    |> assign(:enabled, PhoenixKitCustomerSupport.enabled?())
    |> assign(
      :per_page,
      Settings.get_setting("customer_support_per_page", "20") |> String.to_integer()
    )
    |> assign(
      :internal_notes_enabled,
      Settings.get_boolean_setting("customer_support_internal_notes_enabled", true)
    )
    |> assign(
      :attachments_enabled,
      Settings.get_boolean_setting("customer_support_attachments_enabled", true)
    )
    |> assign(:allow_reopen, Settings.get_boolean_setting("customer_support_allow_reopen", true))
    |> assign(:stats, PhoenixKitCustomerSupport.get_stats())
  end
end
