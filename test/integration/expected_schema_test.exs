defmodule PhoenixKitCustomerSupport.Integration.ExpectedSchemaTest do
  @moduledoc """
  The generated manifest (`PhoenixKitCustomerSupport.ExpectedSchema`) agrees with
  what this module's chain builds, and repair uses it.

  The chain is built alone in a scratch schema
  (`PhoenixKit.TestSupport.ModuleChainCheck.build_alone/4`), then
  `PhoenixKit.Migrations.Repair` runs against that schema with this module's
  manifest. Regenerate the manifest after any change to the chain; see the header
  of `expected_schema.ex`. Excluded (`:requires_core_expected_schema`, see
  `test_helper.exs`) against a core that lacks the callback.
  """
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias PhoenixKit.Migrations.Repair
  alias PhoenixKit.TestSupport.ModuleChainCheck
  alias PhoenixKitCustomerSupport.ExpectedSchema
  alias PhoenixKitCustomerSupport.Migrations
  alias PhoenixKitCustomerSupport.Test.Repo

  @moduletag :integration
  @moduletag :requires_core_expected_schema
  @moduletag timeout: :timer.minutes(3)

  @app :phoenix_kit_customer_support
  @modules %{@app => %{manifest: ExpectedSchema, migrations: Migrations}}

  setup do
    schema = "pkes_" <> Integer.to_string(System.unique_integer([:positive]))
    {:ok, tables} = ModuleChainCheck.build_alone(Repo, Migrations, schema)

    :ok = Sandbox.checkout(Repo)

    on_exit(fn ->
      Sandbox.mode(Repo, :auto)
      Repo.query!(~s(DROP SCHEMA IF EXISTS "#{schema}" CASCADE))
      Sandbox.mode(Repo, :manual)
    end)

    %{schema: schema, tables: tables}
  end

  defp module_findings(report), do: Enum.filter(Repair.Report.findings(report), & &1[:module])

  defp verify(schema) do
    {:ok, report} = Repair.verify(prefix: schema, repo: Repo, module_manifests: @modules)
    report
  end

  test "describes every table the chain builds, and nothing else", %{tables: tables} do
    manifest_tables =
      for %{class: :table, check: {:catalog, %{name: name}}} <- ExpectedSchema.objects("public"),
          do: name

    assert Enum.sort(manifest_tables) == Enum.sort(tables)
  end

  test "a freshly built chain has no findings", %{schema: schema} do
    assert [] = schema |> verify() |> module_findings()
  end

  test "every index and constraint the chain builds is in the manifest", %{schema: schema} do
    ids = MapSet.new(ExpectedSchema.objects(schema), & &1.id)

    %{rows: indexes} =
      Repo.query!(
        "SELECT indexname FROM pg_indexes WHERE schemaname = $1 AND tablename = ANY($2)",
        [schema, Enum.map(ExpectedSchema.objects(schema), & &1.id) |> tables_in()]
      )

    %{rows: constraints} =
      Repo.query!(
        """
        SELECT c.relname, con.conname FROM pg_constraint con
        JOIN pg_class c ON c.oid = con.conrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = $1 AND c.relname = ANY($2) AND con.contype <> 'n'
        """,
        [schema, tables_in(MapSet.to_list(ids))]
      )

    for [name] <- indexes, do: assert(MapSet.member?(ids, "index:#{name}") or pkey?(ids, name))

    for [table, name] <- constraints,
        do: assert(MapSet.member?(ids, "constraint:#{table}.#{name}"))
  end

  test "a missing column is found, then restored by repair", %{schema: schema} do
    Repo.query!(~s(ALTER TABLE "#{schema}"."phoenix_kit_ticket_attachments" DROP COLUMN caption))

    assert [%{kind: :missing, module: @app, object_id: id}] =
             schema |> verify() |> module_findings()

    assert id == "column:phoenix_kit_ticket_attachments.caption"

    {:ok, _report} = Repair.repair(prefix: schema, repo: Repo, module_manifests: @modules)

    assert [] = schema |> verify() |> module_findings()
  end

  defp tables_in(ids) do
    for "table:" <> table <- ids, do: table
  end

  # A primary key or unique constraint's index is listed as the constraint.
  defp pkey?(ids, index_name) do
    Enum.any?(ids, &String.ends_with?(&1, "." <> index_name))
  end
end
