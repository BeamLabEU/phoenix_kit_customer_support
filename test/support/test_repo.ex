defmodule PhoenixKitCustomerSupport.Test.Repo do
  @moduledoc """
  Test-only Ecto repo for integration tests.
  Configured in config/test.exs and started by test_helper.exs.
  """
  use Ecto.Repo,
    otp_app: :phoenix_kit_customer_support,
    adapter: Ecto.Adapters.Postgres
end
