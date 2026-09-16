defmodule PhoenixKitCustomerSupport.MigrationsTest do
  use ExUnit.Case, async: true

  alias PhoenixKitCustomerSupport.Migrations

  @moduledoc """
  Pins the ownership design for `phoenix_kit_customer_support`: this package
  owns all 4 `phoenix_kit_ticket*` tables' FUTURE shape through its module
  migration chain, while core's V135/V164/V168 baseline still creates every
  table on every install, and the chain's V1 merely ADOPTS that shape
  (stamps the `pkcs_schema:` marker on the anchor table, `phoenix_kit_tickets`,
  changes no shape except the documented `changed_by_uuid` correction — see
  `PhoenixKitCustomerSupport.Migrations`' moduledoc).

  Every test here is a pure data/string assertion over
  `up_statements/2`/`down_statements/2`/`up/1`/`down/1`-as-source-text and
  core's static `PhoenixKit.Migrations.ExpectedSchema.objects/1` manifest —
  none of them touch a database.
  """

  @ticket_tables ~w(
    phoenix_kit_tickets
    phoenix_kit_ticket_comments
    phoenix_kit_ticket_attachments
    phoenix_kit_ticket_status_history
  )

  test "PhoenixKitCustomerSupport declares the module-owned migration chain" do
    # Assert the VALUE, not `function_exported?/3` — `use PhoenixKit.Module`
    # injects an overridable default `migration_module/0`, so exportedness
    # says nothing about whether this module declares one.
    assert Code.ensure_loaded?(PhoenixKitCustomerSupport)

    assert PhoenixKitCustomerSupport.migration_module() == Migrations,
           """
           PhoenixKitCustomerSupport no longer declares its migration chain \
           (migration_module/0 returned #{inspect(PhoenixKitCustomerSupport.migration_module())}).

           The chain is how phoenix_kit_customer_support's future shape is versioned
           (pkcs_schema marker) and how `mix phoenix_kit.update` migrates hosts.
           """
  end

  describe "the coordinator implements the protocol" do
    alias PhoenixKit.Migrations.Postgres.Helpers

    test "current_version/0 and version_table/0" do
      assert Migrations.current_version() == 1
      assert Migrations.version_table() == "phoenix_kit_tickets"
    end

    test "initial_version/0" do
      assert Migrations.initial_version() == 1
    end

    # `mix phoenix_kit_hello_world.audit_migrations` (the canonical auditor
    # for this protocol) refuses to drive a coordinator missing any of these
    # five — `mix phoenix_kit.update` itself only calls
    # `migrated_version_runtime/1` + `current_version/0`, but `up/1` needs
    # `migrated_version/1` to re-read the version it is about to change.
    test "exports the full five-function protocol, plus version_table/0 and initial_version/0" do
      for {fun, arity} <- [
            {:current_version, 0},
            {:up, 1},
            {:down, 1},
            {:migrated_version, 1},
            {:migrated_version_runtime, 1},
            {:version_table, 0},
            {:initial_version, 0}
          ] do
        assert function_exported?(Migrations, fun, arity),
               "#{inspect(Migrations)} does not export #{fun}/#{arity}"
      end
    end

    # The marker decides whether any LATER version ever runs: core's
    # `classify/2` reads it and answers `:up_to_date` for every version at or
    # below it. Stamping a version this chain does not have therefore skips
    # V2 and everything after it, silently and permanently.
    test "refuses to stamp a version this chain does not have" do
      too_high = Migrations.current_version() + 1

      assert_raise ArgumentError, ~r/has no version #{too_high}/, fn ->
        Migrations.up_statements("public", too_high)
      end

      assert_raise ArgumentError, ~r/has no version #{too_high}/, fn ->
        Migrations.down_statements("public", too_high)
      end

      # The ceiling itself stays reachable, or the guard would just break
      # the chain instead of bounding it.
      assert Migrations.up_statements("public", Migrations.current_version()) != []
    end

    # This chain interpolates the prefix into every object it creates, and
    # Postgres TRUNCATES an identifier past 63 bytes silently rather than
    # rejecting it — so a prefix core would refuse yields object names that
    # differ from core's while every command still exits 0, breaking the
    # contract adoption rests on. The rules are therefore core's, and this
    # test compares against core rather than restating them.
    test "every public builder that emits SQL validates its own prefix" do
      for fun <- [:up_statements, :down_statements] do
        assert_raise ArgumentError, fn -> apply(Migrations, fun, ["EVIL\";DROP"]) end
        assert_raise ArgumentError, fn -> apply(Migrations, fun, [String.duplicate("a", 30)]) end
        assert_raise ArgumentError, fn -> apply(Migrations, fun, [123]) end
      end
    end

    test "the prefix rules are core's, case and length included" do
      for prefix <- [
            "public",
            "tickets_alt",
            "Tickets",
            "9leading_digit",
            "has-dash",
            String.duplicate("a", 20),
            String.duplicate("a", 21),
            String.duplicate("a", 30)
          ] do
        core_accepts =
          try do
            Helpers.validate_prefix!(prefix)
            true
          rescue
            ArgumentError -> false
          end

        ours_accepts =
          try do
            Migrations.up_statements(prefix)
            true
          rescue
            ArgumentError -> false
          end

        assert ours_accepts == core_accepts,
               "prefix #{inspect(prefix)}: core #{if core_accepts, do: "accepts", else: "rejects"}, " <>
                 "this chain #{if ours_accepts, do: "accepts", else: "rejects"} — the two must agree, " <>
                 "or the object names this chain creates stop matching core's"
      end
    end

    test "rejects a prefix that cannot be safely interpolated into DDL" do
      for bad <- ["public.\"; DROP TABLE x; --", "1st", "a-b", ""] do
        assert_raise ArgumentError, fn -> Migrations.up_statements(bad) end
        assert_raise ArgumentError, fn -> Migrations.down_statements(bad, 0) end
      end
    end
  end

  describe "the chain's per-version statement content is pinned (drift guard)" do
    # V1 is a PUBLISHED version once this ships. A host that has already run
    # it will never run it again, so editing its content does not "fix" that
    # host — it silently splits fresh installs from existing ones. Pinning
    # the exact normalised text makes that split a deliberate, visible diff
    # instead of an accidental one buried in a refactor.
    defp normalised(statements),
      do: Enum.map(statements, &(&1 |> String.replace(~r/\s+/, " ") |> String.trim()))

    test "V1's published statements are frozen" do
      v1 = Migrations.up_statements("public", 1) |> normalised()

      assert v1 == [
               "CREATE TABLE IF NOT EXISTS public.phoenix_kit_tickets ( \"uuid\" uuid DEFAULT public.uuid_generate_v7() NOT NULL, \"title\" character varying(255) NOT NULL, \"description\" text NOT NULL, \"status\" character varying(255) DEFAULT 'open'::character varying NOT NULL, \"slug\" character varying(255) NOT NULL, \"comment_count\" integer DEFAULT 0 NOT NULL, \"metadata\" jsonb DEFAULT '{}'::jsonb, \"resolved_at\" timestamp with time zone, \"closed_at\" timestamp with time zone, \"inserted_at\" timestamp with time zone NOT NULL, \"updated_at\" timestamp with time zone NOT NULL, \"user_uuid\" uuid, \"assigned_to_uuid\" uuid )",
               "CREATE TABLE IF NOT EXISTS public.phoenix_kit_ticket_comments ( \"uuid\" uuid DEFAULT public.uuid_generate_v7() NOT NULL, \"ticket_uuid\" uuid NOT NULL, \"parent_uuid\" uuid, \"content\" text NOT NULL, \"is_internal\" boolean DEFAULT false NOT NULL, \"depth\" integer DEFAULT 0 NOT NULL, \"inserted_at\" timestamp with time zone NOT NULL, \"updated_at\" timestamp with time zone NOT NULL, \"user_uuid\" uuid NOT NULL )",
               "CREATE TABLE IF NOT EXISTS public.phoenix_kit_ticket_attachments ( \"uuid\" uuid DEFAULT public.uuid_generate_v7() NOT NULL, \"ticket_uuid\" uuid, \"comment_uuid\" uuid, \"file_uuid\" uuid NOT NULL, \"position\" integer NOT NULL, \"caption\" text, \"inserted_at\" timestamp with time zone NOT NULL, \"updated_at\" timestamp with time zone NOT NULL )",
               "CREATE TABLE IF NOT EXISTS public.phoenix_kit_ticket_status_history ( \"uuid\" uuid DEFAULT public.uuid_generate_v7() NOT NULL, \"ticket_uuid\" uuid NOT NULL, \"from_status\" character varying(255), \"to_status\" character varying(255) NOT NULL, \"reason\" text, \"inserted_at\" timestamp with time zone NOT NULL, \"changed_by_uuid\" uuid )",
               "ALTER TABLE public.phoenix_kit_ticket_status_history ALTER COLUMN changed_by_uuid DROP NOT NULL",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace WHERE c.conname = 'phoenix_kit_tickets_pkey' AND t.relname = 'phoenix_kit_tickets' AND n.nspname = 'public' ) THEN ALTER TABLE public.phoenix_kit_tickets ADD CONSTRAINT phoenix_kit_tickets_pkey PRIMARY KEY (uuid); END IF; END $$",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace WHERE c.conname = 'phoenix_kit_ticket_comments_pkey' AND t.relname = 'phoenix_kit_ticket_comments' AND n.nspname = 'public' ) THEN ALTER TABLE public.phoenix_kit_ticket_comments ADD CONSTRAINT phoenix_kit_ticket_comments_pkey PRIMARY KEY (uuid); END IF; END $$",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace WHERE c.conname = 'phoenix_kit_ticket_attachments_pkey' AND t.relname = 'phoenix_kit_ticket_attachments' AND n.nspname = 'public' ) THEN ALTER TABLE public.phoenix_kit_ticket_attachments ADD CONSTRAINT phoenix_kit_ticket_attachments_pkey PRIMARY KEY (uuid); END IF; END $$",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace WHERE c.conname = 'phoenix_kit_ticket_status_history_pkey' AND t.relname = 'phoenix_kit_ticket_status_history' AND n.nspname = 'public' ) THEN ALTER TABLE public.phoenix_kit_ticket_status_history ADD CONSTRAINT phoenix_kit_ticket_status_history_pkey PRIMARY KEY (uuid); END IF; END $$",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace WHERE c.conname = 'phoenix_kit_ticket_attachments_parent_check' AND t.relname = 'phoenix_kit_ticket_attachments' AND n.nspname = 'public' ) THEN ALTER TABLE public.phoenix_kit_ticket_attachments ADD CONSTRAINT phoenix_kit_ticket_attachments_parent_check CHECK ((((ticket_uuid IS NOT NULL) AND (comment_uuid IS NULL)) OR ((ticket_uuid IS NULL) AND (comment_uuid IS NOT NULL)))); END IF; END $$",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_tickets_inserted_at_index ON public.phoenix_kit_tickets USING btree (inserted_at)",
               "CREATE UNIQUE INDEX IF NOT EXISTS phoenix_kit_tickets_slug_index ON public.phoenix_kit_tickets USING btree (slug)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_tickets_status_index ON public.phoenix_kit_tickets USING btree (status)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_tickets_status_inserted_at_index ON public.phoenix_kit_tickets USING btree (status, inserted_at)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_tickets_assigned_to_uuid_idx ON public.phoenix_kit_tickets USING btree (assigned_to_uuid)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_tickets_user_uuid_idx ON public.phoenix_kit_tickets USING btree (user_uuid)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_ticket_comments_is_internal_index ON public.phoenix_kit_ticket_comments USING btree (is_internal)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_ticket_comments_parent_id_index ON public.phoenix_kit_ticket_comments USING btree (parent_uuid)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_ticket_comments_ticket_id_index ON public.phoenix_kit_ticket_comments USING btree (ticket_uuid)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_ticket_comments_ticket_id_inserted_at_index ON public.phoenix_kit_ticket_comments USING btree (ticket_uuid, inserted_at)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_ticket_comments_ticket_id_is_internal_index ON public.phoenix_kit_ticket_comments USING btree (ticket_uuid, is_internal)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_ticket_comments_ticket_id_parent_id_depth_index ON public.phoenix_kit_ticket_comments USING btree (ticket_uuid, parent_uuid, depth)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_ticket_comments_user_uuid_idx ON public.phoenix_kit_ticket_comments USING btree (user_uuid)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_ticket_attachments_comment_id_index ON public.phoenix_kit_ticket_attachments USING btree (comment_uuid)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_ticket_attachments_file_id_index ON public.phoenix_kit_ticket_attachments USING btree (file_uuid)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_ticket_attachments_position_index ON public.phoenix_kit_ticket_attachments USING btree (\"position\")",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_ticket_attachments_ticket_id_index ON public.phoenix_kit_ticket_attachments USING btree (ticket_uuid)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_ticket_status_history_inserted_at_index ON public.phoenix_kit_ticket_status_history USING btree (inserted_at)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_ticket_status_history_ticket_id_index ON public.phoenix_kit_ticket_status_history USING btree (ticket_uuid)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_ticket_status_history_ticket_id_inserted_at_index ON public.phoenix_kit_ticket_status_history USING btree (ticket_uuid, inserted_at)",
               "CREATE INDEX IF NOT EXISTS phoenix_kit_ticket_status_history_changed_by_uuid_idx ON public.phoenix_kit_ticket_status_history USING btree (changed_by_uuid)",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace WHERE c.conname = 'fk_tickets_user_uuid' AND t.relname = 'phoenix_kit_tickets' AND n.nspname = 'public' ) THEN ALTER TABLE public.phoenix_kit_tickets ADD CONSTRAINT fk_tickets_user_uuid FOREIGN KEY (user_uuid) REFERENCES public.phoenix_kit_users(uuid) ON DELETE SET NULL; END IF; END $$",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace WHERE c.conname = 'fk_tickets_assigned_to_uuid' AND t.relname = 'phoenix_kit_tickets' AND n.nspname = 'public' ) THEN ALTER TABLE public.phoenix_kit_tickets ADD CONSTRAINT fk_tickets_assigned_to_uuid FOREIGN KEY (assigned_to_uuid) REFERENCES public.phoenix_kit_users(uuid) ON DELETE SET NULL; END IF; END $$",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace WHERE c.conname = 'phoenix_kit_ticket_comments_ticket_id_fkey' AND t.relname = 'phoenix_kit_ticket_comments' AND n.nspname = 'public' ) THEN ALTER TABLE public.phoenix_kit_ticket_comments ADD CONSTRAINT phoenix_kit_ticket_comments_ticket_id_fkey FOREIGN KEY (ticket_uuid) REFERENCES public.phoenix_kit_tickets(uuid) ON DELETE CASCADE; END IF; END $$",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace WHERE c.conname = 'phoenix_kit_ticket_comments_parent_id_fkey' AND t.relname = 'phoenix_kit_ticket_comments' AND n.nspname = 'public' ) THEN ALTER TABLE public.phoenix_kit_ticket_comments ADD CONSTRAINT phoenix_kit_ticket_comments_parent_id_fkey FOREIGN KEY (parent_uuid) REFERENCES public.phoenix_kit_ticket_comments(uuid) ON DELETE CASCADE; END IF; END $$",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace WHERE c.conname = 'fk_ticket_comments_user_uuid' AND t.relname = 'phoenix_kit_ticket_comments' AND n.nspname = 'public' ) THEN ALTER TABLE public.phoenix_kit_ticket_comments ADD CONSTRAINT fk_ticket_comments_user_uuid FOREIGN KEY (user_uuid) REFERENCES public.phoenix_kit_users(uuid) ON DELETE CASCADE; END IF; END $$",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace WHERE c.conname = 'phoenix_kit_ticket_attachments_ticket_id_fkey' AND t.relname = 'phoenix_kit_ticket_attachments' AND n.nspname = 'public' ) THEN ALTER TABLE public.phoenix_kit_ticket_attachments ADD CONSTRAINT phoenix_kit_ticket_attachments_ticket_id_fkey FOREIGN KEY (ticket_uuid) REFERENCES public.phoenix_kit_tickets(uuid) ON DELETE CASCADE; END IF; END $$",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace WHERE c.conname = 'phoenix_kit_ticket_attachments_comment_id_fkey' AND t.relname = 'phoenix_kit_ticket_attachments' AND n.nspname = 'public' ) THEN ALTER TABLE public.phoenix_kit_ticket_attachments ADD CONSTRAINT phoenix_kit_ticket_attachments_comment_id_fkey FOREIGN KEY (comment_uuid) REFERENCES public.phoenix_kit_ticket_comments(uuid) ON DELETE CASCADE; END IF; END $$",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace WHERE c.conname = 'phoenix_kit_ticket_attachments_file_id_fkey' AND t.relname = 'phoenix_kit_ticket_attachments' AND n.nspname = 'public' ) THEN ALTER TABLE public.phoenix_kit_ticket_attachments ADD CONSTRAINT phoenix_kit_ticket_attachments_file_id_fkey FOREIGN KEY (file_uuid) REFERENCES public.phoenix_kit_files(uuid) ON DELETE CASCADE; END IF; END $$",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace WHERE c.conname = 'phoenix_kit_ticket_status_history_ticket_id_fkey' AND t.relname = 'phoenix_kit_ticket_status_history' AND n.nspname = 'public' ) THEN ALTER TABLE public.phoenix_kit_ticket_status_history ADD CONSTRAINT phoenix_kit_ticket_status_history_ticket_id_fkey FOREIGN KEY (ticket_uuid) REFERENCES public.phoenix_kit_tickets(uuid) ON DELETE CASCADE; END IF; END $$",
               "DO $$ BEGIN IF NOT EXISTS ( SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace WHERE c.conname = 'fk_ticket_status_history_changed_by_uuid' AND t.relname = 'phoenix_kit_ticket_status_history' AND n.nspname = 'public' ) THEN ALTER TABLE public.phoenix_kit_ticket_status_history ADD CONSTRAINT fk_ticket_status_history_changed_by_uuid FOREIGN KEY (changed_by_uuid) REFERENCES public.phoenix_kit_users(uuid) ON DELETE SET NULL; END IF; END $$",
               "COMMENT ON TABLE public.phoenix_kit_tickets IS 'pkcs_schema:1'"
             ]
    end
  end

  describe "the chain DDL adopts core's V135/V164/V168 shape" do
    test "V1 uses core's exact object names (shape-identical adoption)" do
      statements = Enum.join(Migrations.up_statements(), "\n")

      for name <- [
            "phoenix_kit_tickets_pkey",
            "phoenix_kit_ticket_comments_pkey",
            "phoenix_kit_ticket_attachments_pkey",
            "phoenix_kit_ticket_status_history_pkey",
            "phoenix_kit_ticket_attachments_parent_check",
            "phoenix_kit_tickets_slug_index",
            "phoenix_kit_tickets_inserted_at_index",
            "phoenix_kit_tickets_status_index",
            "phoenix_kit_tickets_status_inserted_at_index",
            "phoenix_kit_tickets_assigned_to_uuid_idx",
            "phoenix_kit_tickets_user_uuid_idx",
            "phoenix_kit_ticket_comments_is_internal_index",
            "phoenix_kit_ticket_comments_parent_id_index",
            "phoenix_kit_ticket_comments_ticket_id_index",
            "phoenix_kit_ticket_comments_ticket_id_inserted_at_index",
            "phoenix_kit_ticket_comments_ticket_id_is_internal_index",
            "phoenix_kit_ticket_comments_ticket_id_parent_id_depth_index",
            "phoenix_kit_ticket_comments_user_uuid_idx",
            "phoenix_kit_ticket_attachments_comment_id_index",
            "phoenix_kit_ticket_attachments_file_id_index",
            "phoenix_kit_ticket_attachments_position_index",
            "phoenix_kit_ticket_attachments_ticket_id_index",
            "phoenix_kit_ticket_status_history_inserted_at_index",
            "phoenix_kit_ticket_status_history_ticket_id_index",
            "phoenix_kit_ticket_status_history_ticket_id_inserted_at_index",
            "phoenix_kit_ticket_status_history_changed_by_uuid_idx",
            "fk_tickets_user_uuid",
            "fk_tickets_assigned_to_uuid",
            "phoenix_kit_ticket_comments_ticket_id_fkey",
            "phoenix_kit_ticket_comments_parent_id_fkey",
            "fk_ticket_comments_user_uuid",
            "phoenix_kit_ticket_attachments_ticket_id_fkey",
            "phoenix_kit_ticket_attachments_comment_id_fkey",
            "phoenix_kit_ticket_attachments_file_id_fkey",
            "phoenix_kit_ticket_status_history_ticket_id_fkey",
            "fk_ticket_status_history_changed_by_uuid"
          ] do
        assert statements =~ name,
               "V1 no longer creates #{name} — it must stay shape-identical to core's V135/V164/V168"
      end
    end

    test "up stamps the version marker, and stamps it last" do
      statements = Migrations.up_statements()

      assert List.last(statements) ==
               "COMMENT ON TABLE public.phoenix_kit_tickets IS 'pkcs_schema:1'",
             "the marker must be stamped after the DDL it certifies, not before"
    end

    test "applying up to version 0 is not an operation" do
      assert Migrations.up_statements("public", 0) == []
      assert Migrations.up_statements("tickets_alt", 0) == []
    end

    test "every up statement is guarded (IF NOT EXISTS / DO-block idempotence)" do
      # V1 runs on installs where core's V135/V164/V168 already created
      # everything, so every statement must be a no-op against an object
      # that is already there. Two exemptions: the marker COMMENT (not a
      # guarded operation, it's the thing being stamped) and the
      # changed_by_uuid safety-net ALTER — Postgres has no `IF NOT
      # EXISTS`/`IF EXISTS` form for `ALTER COLUMN ... DROP NOT NULL`
      # against an existing column, so its idempotence comes from the
      # statement itself (a no-op against an already-nullable column), not
      # a guard clause. See the moduledoc.
      exempt = [
        "COMMENT ON TABLE public.phoenix_kit_tickets IS 'pkcs_schema:1'",
        "ALTER TABLE public.phoenix_kit_ticket_status_history ALTER COLUMN changed_by_uuid DROP NOT NULL"
      ]

      ddl = Enum.reject(Migrations.up_statements(), &(&1 in exempt))

      for stmt <- ddl do
        assert stmt =~ "IF NOT EXISTS",
               "statement is not idempotent against a core-created table:\n#{stmt}"
      end
    end

    # Section order matters: a table must exist before its safety-net ALTER,
    # pkey, check, index or FK guard runs; the marker must certify a
    # finished shape.
    test "statement sections appear in the order tables -> alter-safety-net -> pkeys -> checks -> indexes -> fks -> marker" do
      statements = Migrations.up_statements()

      sections =
        Enum.map(statements, fn stmt ->
          cond do
            String.starts_with?(stmt, "CREATE TABLE") -> :table
            String.starts_with?(stmt, "ALTER TABLE") -> :alter
            String.starts_with?(stmt, "COMMENT ON TABLE") -> :marker
            String.starts_with?(stmt, "CREATE") -> :index
            String.starts_with?(stmt, "DO") -> :constraint
          end
        end)

      # Every :constraint DO block is a pkey, the one check, or an fk —
      # pkeys and the check are guaranteed to precede indexes (both run
      # back to back, with no index between them, so they dedup into one
      # :constraint run alongside each other) and fks are guaranteed to
      # follow indexes, by construction (see up_statements/2 below).
      # `Enum.dedup/1`, not `Enum.uniq/1`: uniq would collapse the
      # pkey+check :constraint run and the later fk :constraint run into
      # one, silently hiding indexes sorted in between the two.
      order = Enum.dedup(sections)

      assert order == [:table, :alter, :constraint, :index, :constraint, :marker],
             "sections are out of order: #{inspect(order)}"
    end
  end

  describe "the chain can never destroy any of the 4 tables" do
    alias PhoenixKit.Migrations.ExpectedSchema

    # Compared against the WHOLE expected content, not scanned for a
    # forbidden substring — a substring check only sees statements the
    # builder produced, so anything appended past it (a literal
    # `execute("DROP TABLE ...")` in `up/1`) would be invisible to it. That
    # path is closed by the source-text test below, which checks what is
    # executed rather than what is built.
    test "down/1 emits exactly the marker bookkeeping, in every target and prefix" do
      assert Migrations.down_statements("public", 0) ==
               ["COMMENT ON TABLE public.phoenix_kit_tickets IS NULL"]

      assert Migrations.down_statements("public", 1) ==
               ["COMMENT ON TABLE public.phoenix_kit_tickets IS 'pkcs_schema:1'"]

      assert Migrations.down_statements("tickets_alt", 0) ==
               ["COMMENT ON TABLE tickets_alt.phoenix_kit_tickets IS NULL"]

      assert Migrations.down_statements("tickets_alt", 1) ==
               ["COMMENT ON TABLE tickets_alt.phoenix_kit_tickets IS 'pkcs_schema:1'"]
    end

    # For `up/1` the expected content is the full set of OPERATIONS rather
    # than the full SQL text. An operation is `{verb, object}`, immune to
    # reformatting and still failing on any statement added, removed or
    # retargeted — including a destructive one, which cannot enter this set
    # without changing it.
    @up_operations [
      {"CREATE TABLE", "phoenix_kit_tickets"},
      {"CREATE TABLE", "phoenix_kit_ticket_comments"},
      {"CREATE TABLE", "phoenix_kit_ticket_attachments"},
      {"CREATE TABLE", "phoenix_kit_ticket_status_history"},
      {"ALTER TABLE", "phoenix_kit_ticket_status_history"},
      {"DO", "phoenix_kit_tickets_pkey"},
      {"DO", "phoenix_kit_ticket_comments_pkey"},
      {"DO", "phoenix_kit_ticket_attachments_pkey"},
      {"DO", "phoenix_kit_ticket_status_history_pkey"},
      {"DO", "phoenix_kit_ticket_attachments_parent_check"},
      {"CREATE INDEX", "phoenix_kit_tickets_inserted_at_index"},
      {"CREATE UNIQUE INDEX", "phoenix_kit_tickets_slug_index"},
      {"CREATE INDEX", "phoenix_kit_tickets_status_index"},
      {"CREATE INDEX", "phoenix_kit_tickets_status_inserted_at_index"},
      {"CREATE INDEX", "phoenix_kit_tickets_assigned_to_uuid_idx"},
      {"CREATE INDEX", "phoenix_kit_tickets_user_uuid_idx"},
      {"CREATE INDEX", "phoenix_kit_ticket_comments_is_internal_index"},
      {"CREATE INDEX", "phoenix_kit_ticket_comments_parent_id_index"},
      {"CREATE INDEX", "phoenix_kit_ticket_comments_ticket_id_index"},
      {"CREATE INDEX", "phoenix_kit_ticket_comments_ticket_id_inserted_at_index"},
      {"CREATE INDEX", "phoenix_kit_ticket_comments_ticket_id_is_internal_index"},
      {"CREATE INDEX", "phoenix_kit_ticket_comments_ticket_id_parent_id_depth_index"},
      {"CREATE INDEX", "phoenix_kit_ticket_comments_user_uuid_idx"},
      {"CREATE INDEX", "phoenix_kit_ticket_attachments_comment_id_index"},
      {"CREATE INDEX", "phoenix_kit_ticket_attachments_file_id_index"},
      {"CREATE INDEX", "phoenix_kit_ticket_attachments_position_index"},
      {"CREATE INDEX", "phoenix_kit_ticket_attachments_ticket_id_index"},
      {"CREATE INDEX", "phoenix_kit_ticket_status_history_inserted_at_index"},
      {"CREATE INDEX", "phoenix_kit_ticket_status_history_ticket_id_index"},
      {"CREATE INDEX", "phoenix_kit_ticket_status_history_ticket_id_inserted_at_index"},
      {"CREATE INDEX", "phoenix_kit_ticket_status_history_changed_by_uuid_idx"},
      {"DO", "fk_tickets_user_uuid"},
      {"DO", "fk_tickets_assigned_to_uuid"},
      {"DO", "phoenix_kit_ticket_comments_ticket_id_fkey"},
      {"DO", "phoenix_kit_ticket_comments_parent_id_fkey"},
      {"DO", "fk_ticket_comments_user_uuid"},
      {"DO", "phoenix_kit_ticket_attachments_ticket_id_fkey"},
      {"DO", "phoenix_kit_ticket_attachments_comment_id_fkey"},
      {"DO", "phoenix_kit_ticket_attachments_file_id_fkey"},
      {"DO", "phoenix_kit_ticket_status_history_ticket_id_fkey"},
      {"DO", "fk_ticket_status_history_changed_by_uuid"},
      {"COMMENT ON TABLE", "phoenix_kit_tickets"}
    ]

    test "up_statements/2 emits exactly these operations and no others" do
      for prefix <- ["public", "tickets_alt"] do
        actual = Enum.map(Migrations.up_statements(prefix), &operation/1)

        assert Enum.sort(actual) == Enum.sort(@up_operations),
               """
               up_statements(#{inspect(prefix)}) does not emit the expected set of
               operations.

               unexpected: #{inspect(Enum.sort(actual) -- Enum.sort(@up_operations))}
               missing:    #{inspect(Enum.sort(@up_operations) -- Enum.sort(actual))}

               Every statement this chain emits runs against a core-created
               table. Adding one is a chain version (V2+), not something to
               slip past this list.
               """
      end
    end

    # Core's manifest for the 4 ticket tables' index/constraint objects, not
    # a hand-typed list — a hand-typed list is maintained by the same hand
    # that adds a statement, so it catches a slip but never a deliberate
    # one; the manifest is written on core's side, so this fails both when
    # the chain emits an object core does not declare AND when core
    # declares an object the chain stopped adopting. The check constraint
    # and the pkeys are `class: :constraint` in the manifest too, so they
    # are picked up by the same filter as the FKs — no separate handling
    # needed.
    test "up_statements/2 emits exactly the index/constraint operations core's manifest declares for the 4 ticket tables" do
      for prefix <- ["public", "tickets_alt"] do
        actual =
          Migrations.up_statements(prefix, 1)
          |> Enum.reject(
            &(String.starts_with?(&1, "CREATE TABLE") or
                String.starts_with?(&1, "ALTER TABLE") or
                String.starts_with?(&1, "COMMENT ON TABLE"))
          )
          |> Enum.map(&operation/1)

        expected = expected_index_constraint_operations()

        assert Enum.sort(actual) == Enum.sort(expected),
               """
               up_statements(#{inspect(prefix)}, 1) does not emit the operation set
               core's ExpectedSchema declares for the 4 ticket tables' indexes and
               constraints.

               unexpected: #{inspect(Enum.sort(actual) -- Enum.sort(expected))}
               missing:    #{inspect(Enum.sort(expected) -- Enum.sort(actual))}
               """
      end
    end

    test "the 1 real unique index is present, and only it" do
      unique_indexes =
        Migrations.up_statements()
        |> Enum.filter(&String.starts_with?(&1, "CREATE UNIQUE INDEX"))
        |> Enum.map(&operation/1)
        |> Enum.map(&elem(&1, 1))
        |> Enum.sort()

      assert unique_indexes == ["phoenix_kit_tickets_slug_index"]
    end

    defp expected_index_constraint_operations do
      ticket_tables = @ticket_tables

      ExpectedSchema.objects("public")
      |> Enum.filter(fn object ->
        case object.check do
          {_kind, %{table: table}} ->
            table in ticket_tables and object.class in [:index, :constraint] and
              Map.get(object, :presence) == :required

          _ ->
            false
        end
      end)
      |> Enum.map(fn object ->
        name = object.check |> elem(1) |> Map.fetch!(:name)

        case object.class do
          :constraint -> {"DO", name}
          :index -> {index_verb(object.create), name}
        end
      end)
    end

    defp index_verb(create) do
      if String.starts_with?(create, "CREATE UNIQUE INDEX"),
        do: "CREATE UNIQUE INDEX",
        else: "CREATE INDEX"
    end

    # `ON DELETE ...` is part of the foreign key's DEFINITION — the word
    # DELETE there describes what Postgres does to a child row when the
    # PARENT is deleted, and adoption reproducing core's FK means
    # reproducing core's referential action verbatim. Scanning the raw text
    # for the token would flag it, so the clause is removed before the scan.
    defp strip_referential_actions(statement) do
      String.replace(
        statement,
        ~r/ON\s+(DELETE|UPDATE)\s+(CASCADE|RESTRICT|NO\s+ACTION|SET\s+NULL|SET\s+DEFAULT)/i,
        "ON <referential action>"
      )
    end

    test "the referential-action strip does not blind the destructive scan" do
      forbidden = ~r/\b(DROP TABLE|TRUNCATE|DELETE)\b/i

      mutant =
        "ALTER TABLE public.phoenix_kit_ticket_comments ADD CONSTRAINT x FOREIGN KEY (ticket_uuid) " <>
          "REFERENCES public.phoenix_kit_tickets(uuid) ON DELETE CASCADE; DROP TABLE public.phoenix_kit_ticket_comments"

      assert strip_referential_actions(mutant) =~ forbidden

      assert strip_referential_actions("DELETE FROM public.phoenix_kit_tickets") =~ forbidden
      assert strip_referential_actions("TRUNCATE public.phoenix_kit_tickets") =~ forbidden
    end

    test "no statement anywhere in the data-level chain can drop a table, truncate, or delete rows" do
      forbidden = ~r/\b(DROP TABLE|TRUNCATE|DELETE)\b/i

      for prefix <- ["public", "tickets_alt"] do
        for stmt <- Migrations.up_statements(prefix) do
          refute strip_referential_actions(stmt) =~ forbidden,
                 "up_statements(#{inspect(prefix)}) contains: #{stmt}"
        end

        for target <- [0, 1] do
          for stmt <- Migrations.down_statements(prefix, target) do
            refute strip_referential_actions(stmt) =~ forbidden,
                   "down_statements(#{inspect(prefix)}, #{target}) contains: #{stmt}"
          end
        end
      end
    end

    # `{verb, object}` for one statement. The DO block is identified by the
    # constraint it adds, since its verb says nothing about its target.
    defp operation(statement) do
      normalized = statement |> String.replace(~r/\s+/, " ") |> String.trim()

      if String.starts_with?(normalized, "DO ") do
        [_, constraint] = Regex.run(~r/ADD CONSTRAINT (\w+)/, normalized)
        {"DO", constraint}
      else
        [_, verb, object] =
          Regex.run(
            ~r/^(CREATE UNIQUE INDEX|CREATE INDEX|CREATE TABLE|COMMENT ON TABLE|DROP TABLE|DROP INDEX|TRUNCATE|DELETE FROM|ALTER TABLE)(?: IF NOT EXISTS)? (?:\w+\.)?(\w+)/,
            normalized
          )

        {verb, object}
      end
    end
  end

  describe "what reaches the database is what the tests above inspect" do
    # The tests above read `up_statements/2` and `down_statements/2`. The
    # database gets `up/1` and `down/1`. Nothing connected the two, so a
    # literal `execute("DROP TABLE ...")` written straight into `up/1` would
    # have passed every one of them — the guard was watching the data while
    # the function did the work.
    @source "lib/phoenix_kit_customer_support/migrations.ex"

    test "neither direction executes SQL of its own" do
      source = File.read!(@source)

      refute source =~ ~r/execute\(/,
             """
             #{@source} calls execute/1 with an argument of its own.

             Every statement this chain runs must come from up_statements/2 or
             down_statements/2, because those are what the tests above compare
             against their expected content. A statement executed directly is
             invisible to all of them.
             """

      assert length(Regex.scan(~r/&execute\/1/, source)) == 2,
             "expected exactly two `&execute/1` references — one per direction — " <>
               "in #{@source}"
    end

    test "each direction executes its own builder" do
      source = File.read!(@source)

      assert source =~ ~r/up_statements\(opts\.version\)\s*\|>\s*Enum\.each\(&execute\/1\)/,
             "up/1 no longer pipes up_statements/2 into execute/1 — whatever it " <>
               "runs instead is not what the up_statements-based tests above check"

      assert source =~ ~r/down_statements\(opts\.version\)\s*\|>\s*Enum\.each\(&execute\/1\)/,
             "down/1 no longer pipes down_statements/2 into execute/1 — whatever it " <>
               "runs instead is not what `down/1 emits exactly the marker " <>
               "bookkeeping` checks"
    end

    # Scoped to the two functions' own bodies, not the whole file — the
    # moduledoc legitimately discusses "never drops a table" in prose, which
    # a whole-file, case-insensitive scan would flag as a false positive on
    # the English word rather than a SQL token.
    test "up/1 and down/1 themselves contain no DROP/TRUNCATE/DELETE token" do
      source = File.read!(@source)

      [up_body] = Regex.run(~r/def up\(.*?\n  end\n/s, source)
      [down_body] = Regex.run(~r/def down\(.*?\n  end\n/s, source)

      for {name, body} <- [{"up/1", up_body}, {"down/1", down_body}] do
        refute body =~ ~r/DROP|TRUNCATE|DELETE/i,
               "#{name}'s own body in #{@source} contains a DROP/TRUNCATE/DELETE token"
      end
    end
  end

  describe "V1 stays aligned with core's manifest (while core audits the tables)" do
    alias PhoenixKit.Migrations.ExpectedSchema
    alias PhoenixKitCustomerSupport.Ticket
    alias PhoenixKitCustomerSupport.TicketStatusHistory

    @width_schemas %{
      "phoenix_kit_tickets" => Ticket,
      "phoenix_kit_ticket_status_history" => TicketStatusHistory
    }

    # The lesson phoenix_kit_legal paid for once (three disagreeing DDLs of
    # one table): never a second copy of a width. Parsed back out of each
    # CREATE rather than trusted, so a hard-coded number slipped into
    # up_statements/2 instead of a schema's column_widths/0 fails here even
    # though the two happen to agree today.
    test "every varchar width in each CREATE is that table's schema's column_widths/0" do
      statements = Migrations.up_statements("public", 1)

      for {table, schema} <- @width_schemas do
        columns = v1_columns(statements, table)

        parsed =
          columns
          |> Enum.filter(fn {_col, %{type: type}} -> type =~ "character varying" end)
          |> Map.new(fn {col, %{type: type}} ->
            [_, width] = Regex.run(~r/character varying\((\d+)\)/, type)
            {String.to_existing_atom(col), String.to_integer(width)}
          end)

        assert parsed == schema.column_widths(),
               """
               #{table}: the CREATE widths and #{inspect(schema)}.column_widths/0 disagree.

               parsed from DDL: #{inspect(parsed)}
               declared:        #{inspect(schema.column_widths())}
               """
      end
    end

    # Core's V135/V164/V168 baseline still creates these tables and core's
    # ExpectedSchema audits that shape, so until the first shape-changing
    # chain version the two DDLs must agree — with ONE documented exception:
    # `phoenix_kit_ticket_status_history.changed_by_uuid`'s nullability (see
    # the moduledoc). That single field is excluded here and asserted on its
    # own, explicitly, in the next test — so a future manifest fix that
    # makes core agree with us does not silently vanish into a passing test,
    # it makes the next test fail loudly instead.
    test "every column core declares matches V1's, in full, for every table — except the documented changed_by_uuid deviation" do
      statements = Migrations.up_statements("public", 1)

      for table <- @ticket_tables do
        core = core_columns(table)
        ours = v1_columns(statements, table)

        assert Map.keys(ours) -- Map.keys(core) == [],
               "#{table}: V1 creates columns core's manifest does not declare: " <>
                 inspect(Map.keys(ours) -- Map.keys(core))

        assert Map.keys(core) -- Map.keys(ours) == [],
               "#{table}: V1 does not create columns core's manifest declares: " <>
                 inspect(Map.keys(core) -- Map.keys(ours))

        for {column, expected} <- core,
            {table, column} != {"phoenix_kit_ticket_status_history", "changed_by_uuid"} do
          assert Map.fetch!(ours, column) == expected,
                 """
                 #{table}.#{column}: V1 and core's manifest disagree on the column's shape.

                 V1:              #{inspect(Map.fetch!(ours, column))}
                 core's manifest: #{inspect(expected)}

                 V1 is an adoption and must be shape-identical to core's
                 baseline. A deliberate change is a chain version (V2+).
                 """
        end
      end
    end

    test "the changed_by_uuid deviation from core's manifest is exactly the documented one" do
      statements = Migrations.up_statements("public", 1)
      ours = v1_columns(statements, "phoenix_kit_ticket_status_history")
      core = core_columns("phoenix_kit_ticket_status_history")

      ours_shape = Map.fetch!(ours, "changed_by_uuid")
      core_shape = Map.fetch!(core, "changed_by_uuid")

      # V1 deliberately creates this column NULLABLE, matching its FK's
      # `ON DELETE SET NULL` and every real, historically-migrated install
      # — NOT core's literal (self-contradictory) v135.ex/manifest text.
      # See the moduledoc's "changed_by_uuid nullability discrepancy"
      # section. Every OTHER field of the column's shape still matches.
      assert ours_shape.not_null == false
      assert core_shape.not_null == true

      assert Map.delete(ours_shape, :not_null) == Map.delete(core_shape, :not_null),
             "changed_by_uuid diverges from core's manifest in more than just " <>
               "not_null — that is not the documented deviation"
    end

    # `%{type, default, not_null}` per column, from the newest revision.
    defp core_columns(table) do
      prefix = "column:#{table}."

      ExpectedSchema.objects("public")
      |> Enum.filter(&(&1.class == :column and String.starts_with?(&1.id, prefix)))
      |> Map.new(fn object ->
        {_version, shape} = List.last(object.revisions)

        {String.replace_prefix(object.id, prefix, ""),
         %{type: shape.type, default: shape.default, not_null: shape.not_null}}
      end)
    end

    # The same shape, parsed back out of the CREATE TABLE V1 emits for
    # `table`.
    defp v1_columns(statements, table) do
      create = table_create(statements, table)

      ~r/^\s*"(\w+)"\s+(.+?),?$/m
      |> Regex.scan(create)
      |> Map.new(fn [_line, name, definition] -> {name, parse_column(definition)} end)
    end

    defp table_create(statements, table) do
      Enum.find(
        statements,
        &String.starts_with?(&1, "CREATE TABLE IF NOT EXISTS public.#{table} (")
      )
    end

    defp parse_column(definition) do
      {definition, not_null} =
        case String.replace_suffix(definition, " NOT NULL", "") do
          ^definition -> {definition, false}
          trimmed -> {trimmed, true}
        end

      case String.split(definition, " DEFAULT ", parts: 2) do
        [type] -> %{type: type, default: nil, not_null: not_null}
        [type, default] -> %{type: type, default: default, not_null: not_null}
      end
    end
  end
end
