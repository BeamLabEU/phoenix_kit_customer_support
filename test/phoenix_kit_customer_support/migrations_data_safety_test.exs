defmodule PhoenixKitCustomerSupport.MigrationsDataSafetyTest do
  use PhoenixKitCustomerSupport.DataCase, async: false

  alias Ecto.Migration.Runner
  alias PhoenixKitCustomerSupport.Migrations
  alias PhoenixKitCustomerSupport.Ticket
  alias PhoenixKitCustomerSupport.TicketComment
  alias PhoenixKitCustomerSupport.TicketStatusHistory

  @moduledoc """
  The acceptance a table full of real tickets actually needs, and that no
  static test can give: REAL rows, a REAL `down/1` run as a migration, and
  the rows still there afterwards, byte-for-byte.

  `migrations_test.exs` proves what the chain BUILDS (no
  DROP/TRUNCATE/DELETE token anywhere, `down/1` emits marker bookkeeping
  only). That is a proof about text. This file proves what the chain DOES to
  a database that holds a real ticket, a real comment, and a real
  status-history row — on `phoenix_kit_tickets`, the anchor table, and two
  of its dependents.

  The last test is the mutation check: it runs the same survival harness
  against a deliberately destructive rollback and requires it to FAIL.
  Without that, a survival assertion that silently stopped asserting (wrong
  table name, empty row set) would stay green forever and prove nothing.

  `async: false` — the migrator wants the shared sandbox connection.
  """

  defmodule RollbackToZero do
    @moduledoc false
    use Ecto.Migration

    def up, do: Migrations.down(prefix: "public", version: 0)
    def down, do: :ok
  end

  defmodule RollbackToOneFromMap do
    @moduledoc false
    use Ecto.Migration

    # Deliberately the MAP shape: it is accepted, so it must carry
    # `:version` like the keyword list does.
    def up, do: Migrations.down(%{prefix: "public", version: 1})
    def down, do: :ok
  end

  defmodule DestructiveRollback do
    @moduledoc false
    use Ecto.Migration

    # NOT what the package ships — the mutant the survival check must catch.
    def up do
      execute("DELETE FROM public.phoenix_kit_ticket_status_history")
      execute("DELETE FROM public.phoenix_kit_ticket_comments")
      execute("DELETE FROM public.phoenix_kit_tickets")
    end

    def down, do: :ok
  end

  defmodule RunUpToOne do
    @moduledoc false
    use Ecto.Migration

    def up, do: Migrations.up(prefix: "public", version: 1)
    def down, do: :ok
  end

  defp user! do
    n = System.unique_integer([:positive])

    # Direct insert: registration runs the rate limiter, whose ETS backend is
    # not started in this suite, and no test here is about registration.
    %PhoenixKit.Users.Auth.User{}
    |> Ecto.Changeset.change(%{
      email: "reporter-#{n}@example.com",
      hashed_password: Bcrypt.hash_pwd_salt("ValidPassword123!"),
      confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second),
      is_active: true
    })
    |> Repo.insert!()
  end

  setup do
    user = user!()

    {:ok, ticket} =
      PhoenixKitCustomerSupport.create_ticket(user.uuid, %{
        "title" => "Data safety ticket",
        "description" => "Testing rollback safety."
      })

    {:ok, comment} =
      PhoenixKitCustomerSupport.create_comment(ticket.uuid, user.uuid, %{
        "content" => "Looking into it."
      })

    # create_ticket/2 already inserted one status-history row (the initial
    # "-> open" transition) via create_status_history/5 — no separate
    # transition call is needed to have a real row to assert against.
    [status_history] = PhoenixKitCustomerSupport.get_status_history(ticket.uuid)

    {:ok, ticket: ticket, comment: comment, status_history: status_history}
  end

  test "a real down(version: 0) leaves the seeded ticket, comment and status history alive",
       %{ticket: ticket, comment: comment, status_history: status_history} do
    ticket_count = count("phoenix_kit_tickets")
    comment_count = count("phoenix_kit_ticket_comments")
    status_history_count = count("phoenix_kit_ticket_status_history")

    run_migration(RollbackToZero)

    assert count("phoenix_kit_tickets") == ticket_count,
           "rolling this chain back changed the row count in phoenix_kit_tickets"

    assert count("phoenix_kit_ticket_comments") == comment_count,
           "rolling this chain back changed the row count in phoenix_kit_ticket_comments"

    assert count("phoenix_kit_ticket_status_history") == status_history_count,
           "rolling this chain back changed the row count in phoenix_kit_ticket_status_history"

    reloaded_ticket = Repo.get!(Ticket, ticket.uuid)
    assert reloaded_ticket.title == ticket.title
    assert reloaded_ticket.slug == ticket.slug
    assert reloaded_ticket.status == ticket.status

    reloaded_comment = Repo.get!(TicketComment, comment.uuid)
    assert reloaded_comment.content == comment.content
    assert reloaded_comment.ticket_uuid == comment.ticket_uuid

    reloaded_status_history = Repo.get!(TicketStatusHistory, status_history.uuid)
    assert reloaded_status_history.to_status == status_history.to_status
    assert reloaded_status_history.ticket_uuid == status_history.ticket_uuid
  end

  test "the rollback still does its one real job: the marker is cleared" do
    Repo.query!("COMMENT ON TABLE phoenix_kit_tickets IS 'pkcs_schema:1'")
    assert Migrations.migrated_version_runtime(prefix: "public") == 1

    run_migration(RollbackToZero)

    assert Migrations.migrated_version_runtime(prefix: "public") == 0
  end

  test "a rollback to version 1 passed as a map stops at 1, not at 0" do
    Repo.query!("COMMENT ON TABLE phoenix_kit_tickets IS 'pkcs_schema:1'")

    run_migration(RollbackToOneFromMap)

    assert Migrations.migrated_version_runtime(prefix: "public") == 1,
           "the map shape lost :version and rolled the chain further back than asked"
  end

  test "a real up(version: 1) run is idempotent and leaves seeded rows untouched",
       %{ticket: ticket, comment: comment, status_history: status_history} do
    # up/1 re-reads the installed version, calls ensure_extension!/1 and
    # ensure_uuid_v7_function/1, then runs the same 42 guarded statements
    # up_statements/2 emits — clearing the marker first simulates the
    # "database behind the target" branch up/1 checks before doing anything,
    # so this exercises that whole path for real rather than as SQL text
    # applied directly (test_helper.exs does the latter, once, before any
    # test runs — this is the only place up/1 itself, as a function, gets a
    # real migration-context run).
    ticket_count = count("phoenix_kit_tickets")
    comment_count = count("phoenix_kit_ticket_comments")
    status_history_count = count("phoenix_kit_ticket_status_history")

    Repo.query!("COMMENT ON TABLE phoenix_kit_tickets IS NULL")

    run_migration(RunUpToOne)

    assert Migrations.migrated_version_runtime(prefix: "public") == 1

    assert count("phoenix_kit_tickets") == ticket_count,
           "a real up(version: 1) run changed the row count in phoenix_kit_tickets"

    assert count("phoenix_kit_ticket_comments") == comment_count,
           "a real up(version: 1) run changed the row count in phoenix_kit_ticket_comments"

    assert count("phoenix_kit_ticket_status_history") == status_history_count,
           "a real up(version: 1) run changed the row count in phoenix_kit_ticket_status_history"

    assert Repo.get!(Ticket, ticket.uuid).title == ticket.title
    assert Repo.get!(TicketComment, comment.uuid).content == comment.content

    assert Repo.get!(TicketStatusHistory, status_history.uuid).to_status ==
             status_history.to_status

    # Idempotence: every table/pkey/check/index/fk statement is
    # CREATE-IF-NOT-EXISTS/DO-guarded against objects that already exist
    # (core's baseline created them), so running up/1 again must be a no-op,
    # not an error.
    run_migration(RunUpToOne)
    assert Migrations.migrated_version_runtime(prefix: "public") == 1
  end

  test "the survival check has teeth: a destructive rollback fails it", %{ticket: ticket} do
    ticket_count = count("phoenix_kit_tickets")

    run_migration(DestructiveRollback)

    # The same assertions the real test makes. Both must fail here, or the
    # real test above is decoration.
    assert_raise ExUnit.AssertionError, fn ->
      assert count("phoenix_kit_tickets") == ticket_count
    end

    assert_raise Ecto.NoResultsError, fn ->
      Repo.get!(Ticket, ticket.uuid)
    end
  end

  # ── helpers ──────────────────────────────────────────────────────────

  # Runs the migration IN THIS PROCESS, through Ecto's own migration runner,
  # rather than `Ecto.Migrator.up/4`. The Migrator runs the migration inside a
  # `Task`, which then has to check out the sandbox connection this test
  # already owns — it never gets it, and every assertion below dies in the
  # checkout queue instead of testing the rollback. The runner is what the
  # Migrator itself calls once it has dealt with locking and version
  # bookkeeping; going straight to it keeps the real migration context (so
  # `execute/1` inside `down/1` is the real `execute/1`) and drops only the
  # parts this file is not about.
  defp run_migration(module) do
    Runner.run(
      Repo,
      [],
      :os.system_time(:microsecond),
      module,
      :forward,
      :up,
      :up,
      log: false,
      log_migrations_sql: false
    )
  end

  defp count(table) do
    %{rows: [[count]]} = Repo.query!("SELECT count(*) FROM #{table}")
    count
  end
end
