defmodule PhoenixKitCustomerSupport.MigrationsV2Test do
  use ExUnit.Case, async: true

  alias PhoenixKitCustomerSupport.Migrations

  test "V2 adds the nullable guest columns, the email index and a nullable comment author" do
    stmts = Migrations.up_statements("public", 2)

    for col <- [
          "guest_name character varying(255)",
          "guest_email character varying(255)",
          "guest_verified_at timestamp with time zone"
        ] do
      assert "ALTER TABLE public.phoenix_kit_tickets ADD COLUMN IF NOT EXISTS #{col}" in stmts
    end

    assert Enum.any?(
             stmts,
             &(&1 =~
                 "CREATE INDEX IF NOT EXISTS phoenix_kit_tickets_guest_email_idx ON public.phoenix_kit_tickets USING btree (lower((guest_email)::text)) WHERE guest_email IS NOT NULL")
           )

    assert "ALTER TABLE public.phoenix_kit_ticket_comments ALTER COLUMN user_uuid DROP NOT NULL" in stmts
    refute Enum.any?(stmts, &(&1 =~ ~r/NOT NULL DEFAULT|SET NOT NULL/))

    assert List.last(stmts) == "COMMENT ON TABLE public.phoenix_kit_tickets IS 'pkcs_schema:2'"
  end

  test "V2's varchar widths come from Ticket.column_widths/0" do
    widths = PhoenixKitCustomerSupport.Ticket.column_widths()
    joined = Enum.join(Migrations.up_statements("public", 2), "\n")

    assert joined =~ "guest_name character varying(#{widths.guest_name})"
    assert joined =~ "guest_email character varying(#{widths.guest_email})"
  end

  test "V2 runs after V1 and V1 alone emits none of it" do
    v1 = Migrations.up_statements("public", 1)
    refute Enum.join(v1, "\n") =~ "guest_"
    assert List.last(v1) == "COMMENT ON TABLE public.phoenix_kit_tickets IS 'pkcs_schema:1'"

    v2 = Migrations.up_statements("public", 2)
    assert Enum.take(v2, length(v1) - 1) == Enum.drop(v1, -1)
  end

  test "the prefix reaches every V2 statement" do
    for stmt <-
          Migrations.up_statements("tickets_alt", 2) -- Migrations.up_statements("tickets_alt", 1),
        not String.starts_with?(stmt, "COMMENT") do
      assert stmt =~ "tickets_alt."
    end
  end

  test "rolling back to V1 only re-stamps the marker" do
    assert Migrations.down_statements("public", 1) ==
             ["COMMENT ON TABLE public.phoenix_kit_tickets IS 'pkcs_schema:1'"]
  end
end
