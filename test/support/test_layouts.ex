defmodule PhoenixKitCustomerSupport.Test.Layouts do
  @moduledoc """
  Minimal layouts for the test endpoint, and the stand-in for the host
  layout core's `LayoutWrapper.app_layout` renders into (`config
  :phoenix_kit, layout:` in config/test.exs) — core's own root layout needs
  core's endpoint, which module tests do not start.
  """

  use Phoenix.Component

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="csrf-token" content={Phoenix.Controller.get_csrf_token()} />
        <title>Test</title>
      </head>
      <body>
        {@inner_content}
      </body>
    </html>
    """
  end

  def app(assigns) do
    ~H"""
    {@inner_content}
    """
  end

  def public(assigns) do
    ~H"""
    <div id="test-public-layout">{@inner_content}</div>
    """
  end

  def render(_template, _assigns), do: "error"
end
