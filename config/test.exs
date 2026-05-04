import Config

# Integration tests need a real PostgreSQL database. Create it with:
#   createdb phoenix_kit_customer_support_test
config :phoenix_kit_customer_support, ecto_repos: [PhoenixKitCustomerSupport.Test.Repo]

config :phoenix_kit_customer_support, PhoenixKitCustomerSupport.Test.Repo,
  username: System.get_env("PGUSER", "postgres"),
  password: System.get_env("PGPASSWORD", "postgres"),
  hostname: System.get_env("PGHOST", "localhost"),
  database: "phoenix_kit_customer_support_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :phoenix_kit, repo: PhoenixKitCustomerSupport.Test.Repo

config :logger, level: :warning
