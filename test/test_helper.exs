alias PhoenixKitCustomerSupport.Test.Repo, as: TestRepo

db_config = Application.get_env(:phoenix_kit_customer_support, TestRepo, [])
db_name = db_config[:database] || "phoenix_kit_customer_support_test"

db_check =
  try do
    case System.cmd("psql", ["-lqt"], stderr_to_stdout: true) do
      {output, 0} ->
        exists =
          output
          |> String.split("\n")
          |> Enum.any?(fn line ->
            line |> String.split("|") |> List.first("") |> String.trim() == db_name
          end)

        if exists, do: :exists, else: :not_found

      _ ->
        :try_connect
    end
  rescue
    _ -> :try_connect
  end

repo_available =
  if db_check == :not_found do
    IO.puts("""
    \n  Test database "#{db_name}" not found — integration tests excluded.
       Run: createdb #{db_name}
    """)

    false
  else
    try do
      {:ok, _} = TestRepo.start_link()
      TestRepo.query!("CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\"")

      TestRepo.query!("""
      CREATE OR REPLACE FUNCTION uuid_generate_v7()
      RETURNS uuid AS $$
      DECLARE
        unix_ts_ms bytea;
        uuid_bytes bytea;
      BEGIN
        unix_ts_ms := substring(int8send(floor(extract(epoch FROM clock_timestamp()) * 1000)::bigint) FROM 3);
        uuid_bytes := unix_ts_ms || gen_random_bytes(10);
        uuid_bytes := set_byte(uuid_bytes, 6, (get_byte(uuid_bytes, 6) & 15) | 112);
        uuid_bytes := set_byte(uuid_bytes, 8, (get_byte(uuid_bytes, 8) & 63) | 128);
        RETURN encode(uuid_bytes, 'hex')::uuid;
      END;
      $$ LANGUAGE plpgsql VOLATILE;
      """)

      Ecto.Adapters.SQL.Sandbox.mode(TestRepo, :manual)
      true
    rescue
      e ->
        IO.puts("""
        \n  Could not connect to test database — integration tests excluded.
           Error: #{Exception.message(e)}
        """)

        false
    catch
      :exit, reason ->
        IO.puts("""
        \n  Could not connect to test database — integration tests excluded.
           Error: #{inspect(reason)}
        """)

        false
    end
  end

Application.put_env(:phoenix_kit_customer_support, :test_repo_available, repo_available)

{:ok, _pid} = PhoenixKit.PubSub.Manager.start_link([])
{:ok, _pid} = PhoenixKit.ModuleRegistry.start_link([])

require Logger

# i18n tests require phoenix_kit with the `gettext_backend` API
# (see BeamLabEU/phoenix_kit#522). Until that ships in a Hex release,
# CI building against the published phoenix_kit lacks
# `PhoenixKit.Dashboard.Tab.localized_label/1` and the assertions
# would raise `UndefinedFunctionError`. Detect availability and
# exclude those tests when the API is missing — they run automatically
# the moment the consumer's `phoenix_kit` dep resolves to a release
# that includes the API.
i18n_api_available =
  if Code.ensure_loaded?(PhoenixKit.Dashboard.Tab) and
       function_exported?(PhoenixKit.Dashboard.Tab, :localized_label, 1) do
    true
  else
    Logger.info(
      "[test_helper] PhoenixKit.Dashboard.Tab.localized_label/1 not available — " <>
        "i18n tests excluded. They will run automatically once `phoenix_kit` is " <>
        "upgraded to a release that ships the gettext_backend API."
    )

    false
  end

exclude = if repo_available, do: [], else: [:integration]
exclude = if i18n_api_available, do: exclude, else: [:requires_phoenix_kit_i18n_api | exclude]

ExUnit.start(exclude: exclude)
