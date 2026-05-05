defmodule PhoenixKitCustomerSupport.Uploads do
  @moduledoc false

  @doc """
  Classifies a file_type bucket from a MIME content_type.

  Returns "image", "video", "audio", or "document".
  """
  @spec file_type_from_mime(String.t() | nil) :: String.t()
  def file_type_from_mime(mime) when is_binary(mime) do
    cond do
      String.starts_with?(mime, "image/") -> "image"
      String.starts_with?(mime, "video/") -> "video"
      String.starts_with?(mime, "audio/") -> "audio"
      true -> "document"
    end
  end

  def file_type_from_mime(_), do: "document"
end
