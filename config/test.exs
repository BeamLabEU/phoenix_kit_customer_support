import Config

# Integration tests need a real PostgreSQL database. Create it with:
#   createdb phoenix_kit_customer_support_test
config :phoenix_kit_customer_support, ecto_repos: [PhoenixKitCustomerSupport.Test.Repo]

# `PGDATABASE` points the suite at a database the test role cannot CREATE
# (a shared instance). Unset or blank, the old name is used, so CI and a
# local `createdb` are unaffected.
pg_test_db =
  case System.get_env("PGDATABASE", "") |> String.trim() do
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

config :phoenix_kit, repo: PhoenixKitCustomerSupport.Test.Repo

config :logger, level: :warning
