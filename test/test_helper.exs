alias PhoenixKitCustomerSupport.Test.Repo, as: TestRepo

db_config = Application.get_env(:phoenix_kit_customer_support, TestRepo, [])
db_name = db_config[:database] || "phoenix_kit_customer_support_test"

db_check =
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

exclude = if repo_available, do: [], else: [:integration]

ExUnit.start(exclude: exclude)
