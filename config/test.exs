import Config

# Integration tests need a real PostgreSQL database. Create it with:
#   createdb phoenix_kit_customer_support_test
config :phoenix_kit_customer_support, ecto_repos: [PhoenixKitCustomerSupport.Test.Repo]

# Set CUSTOMER_SUPPORT_TEST_DATABASE to use a pre-provisioned test database.
pg_test_db =
  case System.get_env("CUSTOMER_SUPPORT_TEST_DATABASE", "") |> String.trim() do
    "" -> "phoenix_kit_customer_support_test#{System.get_env("MIX_TEST_PARTITION")}"
    value -> value
  end

config :phoenix_kit_customer_support, PhoenixKitCustomerSupport.Test.Repo,
  username: System.get_env("PGUSER", "postgres"),
  password: System.get_env("PGPASSWORD", "postgres"),
  hostname: System.get_env("PGHOST", "localhost"),
  database: pg_test_db,
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# The endpoint signs guest links (`Phoenix.Token`); the layout stands in
# for the host's, which core's `LayoutWrapper.app_layout` renders into.
config :phoenix_kit,
  repo: PhoenixKitCustomerSupport.Test.Repo,
  endpoint: PhoenixKitCustomerSupport.Test.Endpoint,
  layout: {PhoenixKitCustomerSupport.Test.Layouts, :public}

# Test endpoint for the guest-page LiveView tests (the host provides the
# real one).
config :phoenix_kit_customer_support, PhoenixKitCustomerSupport.Test.Endpoint,
  secret_key_base: String.duplicate("c", 64),
  live_view: [signing_salt: "customer-support-test-salt"],
  server: false,
  url: [host: "localhost"],
  render_errors: [formats: [html: PhoenixKitCustomerSupport.Test.Layouts]]

# Guest emails land in the test process (Swoosh test adapter).
config :phoenix_kit, PhoenixKit.Mailer, adapter: Swoosh.Adapters.Test

config :phoenix, :json_library, Jason

config :logger, level: :warning
