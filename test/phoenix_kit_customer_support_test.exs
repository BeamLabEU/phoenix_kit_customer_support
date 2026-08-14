defmodule PhoenixKitCustomerSupportTest do
  use ExUnit.Case, async: true

  test "module exists" do
    assert Code.ensure_loaded?(PhoenixKitCustomerSupport)
  end

  test "version/0 matches mix.exs" do
    assert PhoenixKitCustomerSupport.version() == Mix.Project.config()[:version]
  end
end
