defmodule PhoenixKitCustomerSupport.Uploads do
  @moduledoc false

  require Logger

  alias PhoenixKit.Modules.Storage
  alias PhoenixKit.Users.Auth

  @doc """
  Classifies a file_type bucket from a MIME content_type.

  Returns "image", "video", "audio", or "document".

  `entry.client_type` is browser-supplied, so the result drives bucket
  layout and variant generation only — never authorization.
  """
  @spec file_type_from_mime(term()) :: String.t()
  def file_type_from_mime(mime) when is_binary(mime) do
    cond do
      String.starts_with?(mime, "image/") -> "image"
      String.starts_with?(mime, "video/") -> "video"
      String.starts_with?(mime, "audio/") -> "audio"
      true -> "document"
    end
  end

  def file_type_from_mime(_), do: "document"

  @doc """
  Consumes one done? upload entry into Storage.

  Returns `{:ok, %File{}}` on success, `{:error, client_name}` on storage
  failure so the caller can surface a per-file error in the UI.
  """
  @spec consume_entry(
          Phoenix.LiveView.Socket.t(),
          Phoenix.LiveView.UploadEntry.t(),
          map(),
          String.t()
        ) :: {:ok, struct()} | {:error, String.t()}
  def consume_entry(socket, entry, current_user, label) do
    result =
      Phoenix.LiveView.consume_uploaded_entry(socket, entry, fn %{path: path} ->
        ext = Path.extname(entry.client_name) |> String.replace_leading(".", "")
        file_hash = Auth.calculate_file_hash(path)

        case Storage.store_file_in_buckets(
               path,
               file_type_from_mime(entry.client_type),
               current_user.uuid,
               file_hash,
               ext,
               entry.client_name
             ) do
          {:ok, file, :duplicate} ->
            Logger.info("#{label} attachment is duplicate with ID: #{file.uuid}")
            {:ok, file}

          {:ok, file} ->
            Logger.info("#{label} attachment stored with ID: #{file.uuid}")
            {:ok, file}

          {:error, reason} ->
            Logger.error("Storage error for #{entry.client_name}: #{inspect(reason)}")
            {:ok, nil}
        end
      end)

    case result do
      %_{} = file -> {:ok, file}
      _ -> {:error, entry.client_name}
    end
  end

  @doc """
  Cancels errored upload entries (`:not_accepted`, `:too_large`, etc.) so a
  subsequent `consume_uploaded_entries/3` does not raise on them.
  """
  @spec cancel_errored_entries(Phoenix.LiveView.Socket.t(), atom()) :: Phoenix.LiveView.Socket.t()
  def cancel_errored_entries(socket, name) do
    upload = Map.get(socket.assigns.uploads, name)

    refs =
      Enum.uniq(
        Enum.map(upload.errors, fn {ref, _} -> ref end) ++
          for(entry <- upload.entries, not entry.valid?, do: entry.ref)
      )

    Enum.reduce(refs, socket, &Phoenix.LiveView.cancel_upload(&2, name, &1))
  end
end
