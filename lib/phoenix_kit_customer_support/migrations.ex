defmodule PhoenixKitCustomerSupport.Migrations do
  @moduledoc """
  Module-owned versioned migrations for `phoenix_kit_customer_support` — the
  decentralized-migrations protocol that core's `mix phoenix_kit.update`
  discovers via `migration_module/0`. This follows the canonical shape
  documented in `phoenix_kit_hello_world`'s README ("Versioned migrations",
  "Adopting a table core already creates") and its
  `mix phoenix_kit_hello_world.audit_migrations` task: **two readers**
  (`migrated_version/1` for migration context, `migrated_version_runtime/1`
  for Mix-task context), `up/1` re-reading the version before it changes
  anything, and a namespaced `COMMENT ON TABLE` marker on one anchor table.
  `phoenix_kit_posts` (`v1_statements/2`, 13 adopted tables in one version)
  is the closest sibling example of this exact adoption situation.

  ## Ownership situation — read before touching

  All 4 `phoenix_kit_ticket*` tables are core's baseline: `V135` created all
  4 in their current shape, `V164` deliberately left
  `phoenix_kit_ticket_status_history.changed_by_uuid` out of its NOT NULL
  enforcement pass (see "The `changed_by_uuid` nullability discrepancy"
  below), and `V168` made `phoenix_kit_tickets_slug_index` UNIQUE (repairing
  any existing duplicate slugs first — `Ticket.changeset/2` calls
  `PhoenixKit.Utils.Slug.put_slug/3`, which needs that index to make
  collisions visible). On every existing install all 4 already have their
  full current shape before this chain ever executes — this is an ADOPTION,
  not a create. Varchar widths are never restated as a second number:
  `Ticket.column_widths/0` and `TicketStatusHistory.column_widths/0` are the
  single shape authority this chain's DDL interpolates (`TicketComment` and
  `TicketAttachment` have no varchar column).

  Rather than stamp all 4 tables, the chain anchors its version marker on a
  single table — `phoenix_kit_tickets` itself, this module's own central,
  load-bearing table (the same reasoning `phoenix_kit_posts` used to pick
  `phoenix_kit_posts` over `phoenix_kit_post_tags`: the "table with no
  outgoing FK" convention would point at `phoenix_kit_ticket_status_history`
  here, but that table is not what every other adoption in this chain
  ultimately points back to, and is not at risk of being dropped
  independently of the rest of the chain — which is what the anchor choice
  is actually protecting). `phoenix_kit_ticket_comments`,
  `phoenix_kit_ticket_attachments` and `phoenix_kit_ticket_status_history`
  all carry a real FK to `phoenix_kit_tickets(uuid) ON DELETE CASCADE`
  (`phoenix_kit_ticket_attachments.ticket_uuid` is nullable — an attachment
  belongs to a ticket XOR a comment — but CASCADEs when it is set).

  In total this chain adopts 10 FKs: 2 from `phoenix_kit_tickets` to
  `phoenix_kit_users` (`user_uuid`, `assigned_to_uuid`, both `ON DELETE SET
  NULL`), 3 to `phoenix_kit_tickets` itself (`phoenix_kit_ticket_comments`,
  `phoenix_kit_ticket_attachments`, `phoenix_kit_ticket_status_history`, all
  `ON DELETE CASCADE`), 1 self-referential on `phoenix_kit_ticket_comments`
  (`parent_uuid`, `CASCADE`), 1 from `phoenix_kit_ticket_comments` to
  `phoenix_kit_users` (`user_uuid`, `CASCADE`), 2 from
  `phoenix_kit_ticket_attachments` (`comment_uuid` to
  `phoenix_kit_ticket_comments`, `CASCADE`; `file_uuid` to
  `phoenix_kit_files`, `CASCADE`), and 1 from
  `phoenix_kit_ticket_status_history` to `phoenix_kit_users`
  (`changed_by_uuid`, `SET NULL`).

  ### The `changed_by_uuid` nullability discrepancy

  `phoenix_kit_ticket_status_history.changed_by_uuid` is deliberately
  NULLABLE in this chain's `CREATE TABLE`, which does **not** match core's
  literal `v135.ex` source text (`"changed_by_uuid" uuid NOT NULL`). This is
  a documented, deliberate deviation from that literal text — not a slip:

    * `v135.ex`'s `CREATE TABLE` text has `"changed_by_uuid" uuid NOT NULL`.
    * The column's own FK (`fk_ticket_status_history_changed_by_uuid`) is
      `ON DELETE SET NULL` — directly contradicting a NOT NULL column.
    * Core's `v164.ex` moduledoc documents this exact contradiction:
      `{:phoenix_kit_ticket_status_history, "changed_by_uuid"}` is listed in
      V164's `@relaxed_after_v57` — V164 deliberately SKIPS enforcing NOT
      NULL on it (a genuine self-contradiction inside core's own V56/V57 era
      declarations), but V164 never drops the NOT NULL either — it simply
      never touches the column.
    * Core's `ExpectedSchema` manifest is ALSO internally inconsistent here:
      its structured `revisions` field says `not_null: true` for this
      column, but its own `create:` ADD-COLUMN text for the same column
      omits NOT NULL. Both cannot be right given the FK.

  Conclusion: this chain's V1 creates `changed_by_uuid` NULLABLE — matching
  the FK's `ON DELETE SET NULL` semantics, and matching every real install
  that reached today's chain HEAD through the actual historical migration
  path rather than a fresh V135 squash. It does NOT match core's literal
  (self-contradictory, buggy) `v135.ex`/manifest text. Every install made
  from the squashed baseline (core >= 2.0.0) DOES carry core's literal V135
  NOT NULL — verified on a scratch database: after core's `ensure_current`
  the column is `is_nullable = NO`, after this chain's V1 it is `YES`. So on
  those hosts V1 is a real shape change, not a pure adoption, and the
  statement that performs it runs immediately after the `CREATE TABLE` block:
  `ALTER TABLE ... ALTER COLUMN changed_by_uuid DROP NOT NULL` — idempotent,
  since Postgres no-ops `DROP NOT NULL` against an already-nullable column.
  Unlike an `ADD COLUMN IF NOT EXISTS` safety net, Postgres has no `IF NOT
  EXISTS`/`IF EXISTS` form for `ALTER COLUMN ... DROP NOT NULL` against an
  existing column — the statement's own idempotence is what makes it safe to
  re-run, not a guard clause (see the "every up statement is guarded" test:
  this is the one non-marker exemption, alongside the marker `COMMENT`).

  ### A coincidental ownership tag in core's baseline-squash generator

  Core's baseline-squash generator (`dev_docs/squash/generate_baseline.exs`
  in core, not in this repo) tags `phoenix_kit_ticket_comments` as `owner:
  :comments` via a substring-match heuristic on "comment" in the table name
  — it is NOT owned by the `phoenix_kit_comments` module (that module owns
  `phoenix_kit_comments`/`phoenix_kit_comments_likes`/
  `phoenix_kit_comments_dislikes` — plural `comments_`, unrelated tables).
  `PhoenixKitCustomerSupport.TicketComment` in THIS repo is the real owner.
  A `{"ticket_", :customer_support}` prefix rule ahead of the substring
  fallback in core's Phase 1 manifest work (below) would tag all 4 tables
  `:customer_support` instead — proposed here as prose only; core is a
  separate repo and this PR does not edit it.

  ### Phase 0 — this V1 adopts, and changes NOTHING

  `CREATE TABLE IF NOT EXISTS` shape-identical to core's `V135`/`V164`/`V168`
  baseline, under core's exact object names (every pkey, the one check
  constraint, every index, and every FK), then a **namespaced** marker stamp
  on the anchor table (`pkcs_schema:1` — an adopted table may already carry
  a foreign comment, so the reader must treat prose as version 0, never
  crash on it, never assume it means V1). Because the shape is unchanged
  (modulo the documented `changed_by_uuid` correction above), core's
  `ExpectedSchema` manifest stays accurate for every column except that one,
  which is a known, pre-existing manifest bug this chain does not
  reproduce: **no core release is required and there is no
  release-ordering hazard.** This package releases alone.

  ### Phase 1 — the first real shape change (V2+) is when core must move too

  Before shipping a version that changes any of the 4 tables' shape:

    1. add the objects that version alters to core's manifest generator's
       `@excluded_exact` (`dev_docs/squash/generate_baseline.exs`) and
       regenerate `ExpectedSchema`;
    2. raise this package's `:phoenix_kit` floor to the release that ships
       that regenerated manifest.

  Skipping step 1 means `mix phoenix_kit.repair` restores the old shape
  after every run, silently undoing the new version.

  ### Phase 2 — creation leaves core's baseline at the next squash cycle

  When core cuts its next baseline, module-owned tables are simply not
  included: fresh installs from then on get all 4 `phoenix_kit_ticket*`
  tables from THIS chain's V1 — which is why V1's `up/1` ensures the
  `uuid_generate_v7()` function (and its `pgcrypto` extension) exist rather
  than assuming core's chain already provided them, and why the `CREATE
  TABLE` statements must already be the full, correct definition on their
  own, not merely a shape-matching no-op for an already-existing table.
  Existing installs are untouched — a baseline squash only affects fresh
  installs and below-floor bridging.

  ## What must NEVER happen

  No conditional core migration of the form "module absent → drop the
  tables" — that is nondeterministic (depends on which packages are
  compiled in) and destroys data on a host that merely removed the
  package. Removing this module's data is a human, manual step — see
  README.md "Removing this module" for the operator SQL. There is
  deliberately no automated uninstall path, and `down/1` NEVER drops any of
  the 4 tables for ANY target version, including `0` — it only unstamps (or
  re-stamps) the marker on the anchor table. The rows are every customer's
  tickets, comments (public and internal), attachments and status-change
  audit trail, and on every existing install every table is core-created;
  rolling back this module's chain must not destroy any of them.

  The migrated version is tracked as a `pkcs_schema:<N>` COMMENT on
  `phoenix_kit_tickets`. A marker-less table, or one carrying a foreign
  (non-`pkcs_schema:`) comment, reads as version 0 — the core-baseline shape
  before this chain existed.
  """

  use Ecto.Migration

  alias PhoenixKit.Migrations.Postgres.Helpers
  alias PhoenixKitCustomerSupport.Ticket
  alias PhoenixKitCustomerSupport.TicketStatusHistory

  @initial_version 1
  @current_version 1
  @default_prefix "public"
  @marker_prefix "pkcs_schema:"

  @tickets "phoenix_kit_tickets"
  @ticket_comments "phoenix_kit_ticket_comments"
  @ticket_attachments "phoenix_kit_ticket_attachments"
  @ticket_status_history "phoenix_kit_ticket_status_history"

  # The single table this chain's marker lives on — this module's own hub
  # table, not `ticket_status_history` (see the moduledoc for why the usual
  # "FK-free table" convention is set aside here). Every other table adopted
  # below shares this chain's version; none of them carry a marker of their
  # own.
  @version_table @tickets

  @doc "The version this code expects the schema to be at."
  @spec current_version() :: pos_integer()
  def current_version, do: @current_version

  @doc """
  The version a bare, freshly-created set of tables is at (Phase 2 — a
  future install whose core baseline no longer creates these tables).
  """
  @spec initial_version() :: pos_integer()
  def initial_version, do: @initial_version

  @doc """
  The table carrying the `pkcs_schema:<N>` marker for the whole 4-table chain.

  Not part of the protocol `mix phoenix_kit.update` calls. Exported so an
  auditor (`mix phoenix_kit_hello_world.audit_migrations`) can verify the
  marker is really a number without hard-coding this table's name.
  """
  @spec version_table() :: String.t()
  def version_table, do: @version_table

  @doc """
  Applies every chain version up to `opts[:version]` (default
  `current_version/0`). Migration-context only — re-reads the installed
  version via `migrated_version/1` before making any change, so a database
  already at (or ahead of) the target does nothing.
  """
  @spec up(keyword() | map()) :: :ok
  def up(opts \\ []) do
    opts = with_defaults(opts, @current_version)

    if migrated_version(opts) < opts.version do
      # Don't assume core's chain ran first (Phase 2): `uuid_generate_v7()`
      # is built on pgcrypto's `gen_random_bytes`, and
      # `ensure_uuid_v7_function/1` does not install extensions — without
      # the first call the function is created and then fails on the first
      # insert.
      Helpers.ensure_extension!("pgcrypto")
      Helpers.ensure_uuid_v7_function(opts.prefix)

      opts.prefix
      |> up_statements(opts.version)
      |> Enum.each(&execute/1)
    end

    :ok
  end

  @doc """
  Rolls back to `opts[:version]` (default `0`). Migration-context only.
  Never drops a table or a row in any of the 4, for any target — see the
  moduledoc.
  """
  @spec down(keyword() | map()) :: :ok
  def down(opts \\ []) do
    opts = with_defaults(opts, 0)

    if migrated_version(opts) > opts.version do
      opts.prefix
      |> down_statements(opts.version)
      |> Enum.each(&execute/1)
    end

    :ok
  end

  @doc """
  The version currently installed, read INSIDE a migration — through
  `Ecto.Migration`'s own `repo()`. No rescue: inside a migration a version
  that cannot be read must abort the transaction, never be guessed at.
  `up/1` and `down/1` call this — never `migrated_version_runtime/1` —
  before making any change.
  """
  @spec migrated_version(keyword() | map()) :: non_neg_integer()
  def migrated_version(opts \\ []) do
    opts = with_defaults(opts, @initial_version)
    read_version(repo(), opts.prefix)
  end

  @doc """
  Runtime-safe reader — the one `mix phoenix_kit.update` calls, from a Mix
  task with no migrator running, through PhoenixKit's configured repo
  instead of `Ecto.Migration`'s.

  An invalid prefix is re-raised, matching core's own reader: `0` means
  "not installed here", so reporting it for a bad prefix would tell the
  operator something false and send the updater off to install a schema
  over live data. Genuine unreachability still yields `0`, which is safe
  only because `up/1` re-reads the version in migration context before
  touching anything — a wrong `0` costs a redundant migration file, never
  wrong DDL.
  """
  @spec migrated_version_runtime(keyword() | map()) :: non_neg_integer()
  def migrated_version_runtime(opts \\ []) do
    opts = with_defaults(opts, @initial_version)
    read_version(PhoenixKit.RepoHelper.repo(), opts.prefix)
  rescue
    e in ArgumentError -> reraise e, __STACKTRACE__
    _ -> 0
  end

  @doc """
  The SQL `up/1` executes, as data — the testable single source. The
  ownership test suite parses these statements to prove that the object
  names are core's `V135`/`V164`/`V168` names, that every `CREATE TABLE`
  stays shape-identical to core's `ExpectedSchema` manifest (except the
  documented `changed_by_uuid` correction), that every varchar width is its
  owning schema's `column_widths/0`, and that nothing here can drop a table.

  `target` selects how much of the chain to emit (default
  `current_version/0`): `0` applies nothing (not an operation — clearing
  the marker is `down/1`'s job); `1` is the pure `V135`/`V164`/`V168`-adoption
  step across all 4 tables.
  """
  @spec up_statements(String.t(), non_neg_integer()) :: [String.t()]
  def up_statements(prefix \\ @default_prefix, target \\ @current_version)

  def up_statements(prefix, target) when is_integer(target) and target >= 0 do
    validate_target!(target)
    prefix = validated_prefix(prefix)

    if target == 0 do
      []
    else
      v1_statements(prefix, target)
    end
  end

  @doc """
  The SQL `down/1` executes, as data (marker bookkeeping only, on the
  anchor table). V1 changes no shape of its own — it is pure adoption — so
  there is nothing to drop beyond the marker; all 4 tables and every row in
  them are left untouched, for any target including `0`.
  """
  @spec down_statements(String.t(), non_neg_integer()) :: [String.t()]
  def down_statements(prefix \\ @default_prefix, target \\ 0)

  def down_statements(prefix, target) when is_integer(target) and target >= 0 do
    validate_target!(target)
    prefix = validated_prefix(prefix)
    qualified = Helpers.qualify_table(@version_table, prefix)

    if target > 0 do
      ["COMMENT ON TABLE #{qualified} IS '#{@marker_prefix}#{target}'"]
    else
      ["COMMENT ON TABLE #{qualified} IS NULL"]
    end
  end

  # ── V1 statement builder ────────────────────────────────────────────────

  defp v1_statements(prefix, target) do
    users = Helpers.qualify_table("phoenix_kit_users", prefix)
    files = Helpers.qualify_table("phoenix_kit_files", prefix)
    uuid_default = Helpers.uuid_v7_call(prefix)

    q_tickets = Helpers.qualify_table(@tickets, prefix)
    q_ticket_comments = Helpers.qualify_table(@ticket_comments, prefix)
    q_ticket_attachments = Helpers.qualify_table(@ticket_attachments, prefix)
    q_ticket_status_history = Helpers.qualify_table(@ticket_status_history, prefix)

    tw = Ticket.column_widths()
    sw = TicketStatusHistory.column_widths()

    tables = [
      """
      CREATE TABLE IF NOT EXISTS #{q_tickets} (
        "uuid" uuid DEFAULT #{uuid_default} NOT NULL,
        "title" character varying(#{tw.title}) NOT NULL,
        "description" text NOT NULL,
        "status" character varying(#{tw.status}) DEFAULT 'open'::character varying NOT NULL,
        "slug" character varying(#{tw.slug}) NOT NULL,
        "comment_count" integer DEFAULT 0 NOT NULL,
        "metadata" jsonb DEFAULT '{}'::jsonb,
        "resolved_at" timestamp with time zone,
        "closed_at" timestamp with time zone,
        "inserted_at" timestamp with time zone NOT NULL,
        "updated_at" timestamp with time zone NOT NULL,
        "user_uuid" uuid,
        "assigned_to_uuid" uuid
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS #{q_ticket_comments} (
        "uuid" uuid DEFAULT #{uuid_default} NOT NULL,
        "ticket_uuid" uuid NOT NULL,
        "parent_uuid" uuid,
        "content" text NOT NULL,
        "is_internal" boolean DEFAULT false NOT NULL,
        "depth" integer DEFAULT 0 NOT NULL,
        "inserted_at" timestamp with time zone NOT NULL,
        "updated_at" timestamp with time zone NOT NULL,
        "user_uuid" uuid NOT NULL
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS #{q_ticket_attachments} (
        "uuid" uuid DEFAULT #{uuid_default} NOT NULL,
        "ticket_uuid" uuid,
        "comment_uuid" uuid,
        "file_uuid" uuid NOT NULL,
        "position" integer NOT NULL,
        "caption" text,
        "inserted_at" timestamp with time zone NOT NULL,
        "updated_at" timestamp with time zone NOT NULL
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS #{q_ticket_status_history} (
        "uuid" uuid DEFAULT #{uuid_default} NOT NULL,
        "ticket_uuid" uuid NOT NULL,
        "from_status" character varying(#{sw.from_status}),
        "to_status" character varying(#{sw.to_status}) NOT NULL,
        "reason" text,
        "inserted_at" timestamp with time zone NOT NULL,
        "changed_by_uuid" uuid
      )
      """
    ]

    # Safety net for the documented `changed_by_uuid` discrepancy (see
    # moduledoc): a fresh install that only ever ran core's literal V135
    # `CREATE TABLE` (NOT NULL) would need this to reach the nullable shape
    # every real, historically-migrated install already has. No `IF NOT
    # EXISTS`/`IF EXISTS` form exists for `ALTER COLUMN ... DROP NOT NULL`
    # against an existing column — the statement is idempotent on its own
    # (Postgres no-ops it against an already-nullable column).
    safety_net = [
      "ALTER TABLE #{q_ticket_status_history} ALTER COLUMN changed_by_uuid DROP NOT NULL"
    ]

    pkeys =
      for {table, qualified} <- [
            {@tickets, q_tickets},
            {@ticket_comments, q_ticket_comments},
            {@ticket_attachments, q_ticket_attachments},
            {@ticket_status_history, q_ticket_status_history}
          ] do
        pkey_guard(table, qualified, prefix)
      end

    checks = [
      check_guard(
        @ticket_attachments,
        q_ticket_attachments,
        "phoenix_kit_ticket_attachments_parent_check",
        "(((ticket_uuid IS NOT NULL) AND (comment_uuid IS NULL)) OR ((ticket_uuid IS NULL) AND (comment_uuid IS NOT NULL)))",
        prefix
      )
    ]

    indexes =
      [
        {"", "phoenix_kit_tickets_inserted_at_index", q_tickets, "btree", "inserted_at"},
        {"UNIQUE", "phoenix_kit_tickets_slug_index", q_tickets, "btree", "slug"},
        {"", "phoenix_kit_tickets_status_index", q_tickets, "btree", "status"},
        {"", "phoenix_kit_tickets_status_inserted_at_index", q_tickets, "btree",
         "status, inserted_at"},
        {"", "phoenix_kit_tickets_assigned_to_uuid_idx", q_tickets, "btree", "assigned_to_uuid"},
        {"", "phoenix_kit_tickets_user_uuid_idx", q_tickets, "btree", "user_uuid"},
        {"", "phoenix_kit_ticket_comments_is_internal_index", q_ticket_comments, "btree",
         "is_internal"},
        {"", "phoenix_kit_ticket_comments_parent_id_index", q_ticket_comments, "btree",
         "parent_uuid"},
        {"", "phoenix_kit_ticket_comments_ticket_id_index", q_ticket_comments, "btree",
         "ticket_uuid"},
        {"", "phoenix_kit_ticket_comments_ticket_id_inserted_at_index", q_ticket_comments,
         "btree", "ticket_uuid, inserted_at"},
        {"", "phoenix_kit_ticket_comments_ticket_id_is_internal_index", q_ticket_comments,
         "btree", "ticket_uuid, is_internal"},
        {"", "phoenix_kit_ticket_comments_ticket_id_parent_id_depth_index", q_ticket_comments,
         "btree", "ticket_uuid, parent_uuid, depth"},
        {"", "phoenix_kit_ticket_comments_user_uuid_idx", q_ticket_comments, "btree",
         "user_uuid"},
        {"", "phoenix_kit_ticket_attachments_comment_id_index", q_ticket_attachments, "btree",
         "comment_uuid"},
        {"", "phoenix_kit_ticket_attachments_file_id_index", q_ticket_attachments, "btree",
         "file_uuid"},
        {"", "phoenix_kit_ticket_attachments_position_index", q_ticket_attachments, "btree",
         "\"position\""},
        {"", "phoenix_kit_ticket_attachments_ticket_id_index", q_ticket_attachments, "btree",
         "ticket_uuid"},
        {"", "phoenix_kit_ticket_status_history_inserted_at_index", q_ticket_status_history,
         "btree", "inserted_at"},
        {"", "phoenix_kit_ticket_status_history_ticket_id_index", q_ticket_status_history,
         "btree", "ticket_uuid"},
        {"", "phoenix_kit_ticket_status_history_ticket_id_inserted_at_index",
         q_ticket_status_history, "btree", "ticket_uuid, inserted_at"},
        {"", "phoenix_kit_ticket_status_history_changed_by_uuid_idx", q_ticket_status_history,
         "btree", "changed_by_uuid"}
      ]
      |> Enum.map(fn {unique, name, table, method, columns} ->
        "CREATE #{unique_prefix(unique)}INDEX IF NOT EXISTS #{name} ON #{table} USING #{method} (#{columns})"
      end)

    fks = [
      fk_guard(
        @tickets,
        q_tickets,
        "fk_tickets_user_uuid",
        "user_uuid",
        users,
        "SET NULL",
        prefix
      ),
      fk_guard(
        @tickets,
        q_tickets,
        "fk_tickets_assigned_to_uuid",
        "assigned_to_uuid",
        users,
        "SET NULL",
        prefix
      ),
      fk_guard(
        @ticket_comments,
        q_ticket_comments,
        "phoenix_kit_ticket_comments_ticket_id_fkey",
        "ticket_uuid",
        q_tickets,
        "CASCADE",
        prefix
      ),
      fk_guard(
        @ticket_comments,
        q_ticket_comments,
        "phoenix_kit_ticket_comments_parent_id_fkey",
        "parent_uuid",
        q_ticket_comments,
        "CASCADE",
        prefix
      ),
      fk_guard(
        @ticket_comments,
        q_ticket_comments,
        "fk_ticket_comments_user_uuid",
        "user_uuid",
        users,
        "CASCADE",
        prefix
      ),
      fk_guard(
        @ticket_attachments,
        q_ticket_attachments,
        "phoenix_kit_ticket_attachments_ticket_id_fkey",
        "ticket_uuid",
        q_tickets,
        "CASCADE",
        prefix
      ),
      fk_guard(
        @ticket_attachments,
        q_ticket_attachments,
        "phoenix_kit_ticket_attachments_comment_id_fkey",
        "comment_uuid",
        q_ticket_comments,
        "CASCADE",
        prefix
      ),
      fk_guard(
        @ticket_attachments,
        q_ticket_attachments,
        "phoenix_kit_ticket_attachments_file_id_fkey",
        "file_uuid",
        files,
        "CASCADE",
        prefix
      ),
      fk_guard(
        @ticket_status_history,
        q_ticket_status_history,
        "phoenix_kit_ticket_status_history_ticket_id_fkey",
        "ticket_uuid",
        q_tickets,
        "CASCADE",
        prefix
      ),
      fk_guard(
        @ticket_status_history,
        q_ticket_status_history,
        "fk_ticket_status_history_changed_by_uuid",
        "changed_by_uuid",
        users,
        "SET NULL",
        prefix
      )
    ]

    marker = ["COMMENT ON TABLE #{q_tickets} IS '#{@marker_prefix}#{target}'"]

    tables ++ safety_net ++ pkeys ++ checks ++ indexes ++ fks ++ marker
  end

  defp unique_prefix("UNIQUE"), do: "UNIQUE "
  defp unique_prefix(""), do: ""

  defp pkey_guard(table, qualified, prefix) do
    """
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint c
        JOIN pg_class t ON t.oid = c.conrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE c.conname = '#{table}_pkey'
          AND t.relname = '#{table}'
          AND n.nspname = '#{prefix}'
      ) THEN
        ALTER TABLE #{qualified} ADD CONSTRAINT #{table}_pkey PRIMARY KEY (uuid);
      END IF;
    END
    $$
    """
  end

  defp check_guard(table, qualified, constraint_name, check_expr, prefix) do
    """
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint c
        JOIN pg_class t ON t.oid = c.conrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE c.conname = '#{constraint_name}'
          AND t.relname = '#{table}'
          AND n.nspname = '#{prefix}'
      ) THEN
        ALTER TABLE #{qualified} ADD CONSTRAINT #{constraint_name} CHECK (#{check_expr});
      END IF;
    END
    $$
    """
  end

  defp fk_guard(table, qualified, constraint_name, column, references, on_delete, prefix) do
    """
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint c
        JOIN pg_class t ON t.oid = c.conrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE c.conname = '#{constraint_name}'
          AND t.relname = '#{table}'
          AND n.nspname = '#{prefix}'
      ) THEN
        ALTER TABLE #{qualified} ADD CONSTRAINT #{constraint_name} FOREIGN KEY (#{column}) REFERENCES #{references}(uuid) ON DELETE #{on_delete};
      END IF;
    END
    $$
    """
  end

  # ── internals ──────────────────────────────────────────────────────────

  defp with_defaults(opts, version) do
    opts = Enum.into(opts, %{})
    prefix = validated_prefix(Map.get(opts, :prefix) || @default_prefix)

    opts
    |> Map.put(:prefix, prefix)
    |> Map.put_new(:version, version)
  end

  defp read_version(repo, prefix) do
    if table_exists?(repo, prefix) do
      repo |> table_comment(prefix) |> parse_version()
    else
      0
    end
  end

  defp table_exists?(repo, prefix) do
    query = """
    SELECT EXISTS (
      SELECT FROM information_schema.tables
      WHERE table_name = $1 AND table_schema = $2
    )
    """

    case repo.query(query, [@version_table, prefix], log: false) do
      {:ok, %{rows: [[exists?]]}} -> exists?
      {:error, error} -> raise error
    end
  end

  defp table_comment(repo, prefix) do
    query = """
    SELECT pg_catalog.obj_description(c.oid, 'pg_class')
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relname = $1 AND n.nspname = $2
    """

    case repo.query(query, [@version_table, prefix], log: false) do
      {:ok, %{rows: [[comment]]}} -> comment
      {:ok, %{rows: []}} -> nil
      {:error, error} -> raise error
    end
  end

  defp parse_version(@marker_prefix <> n) do
    case Integer.parse(n) do
      {version, ""} when version >= 0 -> version
      _ -> 0
    end
  end

  defp parse_version(_), do: 0

  defp validate_target!(target) when target > @current_version do
    raise ArgumentError,
          "PhoenixKitCustomerSupport.Migrations has no version #{target} " <>
            "(current_version/0 is #{@current_version}); stamping it would make every " <>
            "later version look already applied"
  end

  defp validate_target!(_target), do: :ok

  defp validated_prefix(prefix) do
    if Code.ensure_loaded?(Helpers) and function_exported?(Helpers, :validate_prefix!, 1) do
      Helpers.validate_prefix!(prefix)
    else
      unless is_binary(prefix) and prefix =~ ~r/^[a-z_][a-z0-9_]*$/ and byte_size(prefix) <= 20 do
        raise ArgumentError, "invalid schema prefix: #{inspect(prefix)}"
      end
    end

    prefix
  end
end
