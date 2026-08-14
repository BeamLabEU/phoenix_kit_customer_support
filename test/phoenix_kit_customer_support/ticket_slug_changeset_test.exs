defmodule PhoenixKitCustomerSupport.TicketSlugChangesetTest do
  @moduledoc """
  Changeset-only slug contract. These cases never call `put_slug/3`'s
  uniqueness probe (they either keep an existing slug or generate nothing),
  so they run without Postgres — the integration file is skipped when the
  test database is missing.
  """
  use ExUnit.Case, async: true

  alias Ecto.Changeset
  alias PhoenixKitCustomerSupport.Ticket

  @existing %Ticket{
    uuid: "018e3c4a-9f6b-7890-abcd-ef1234567890",
    user_uuid: "018e3c4a-1111-7890-abcd-ef1234567890",
    title: "Old ticket",
    description: "From before the fix.",
    status: "open",
    slug: "old-ticket-483920"
  }

  describe "an existing slug is left alone" do
    test "a status-only change does not put a slug change" do
      changeset = Ticket.changeset(@existing, %{status: "in_progress"})

      assert changeset.valid?
      assert Changeset.get_change(changeset, :slug) == nil
      assert Changeset.get_field(changeset, :slug) == "old-ticket-483920"
    end

    test "a title change does not regenerate" do
      changeset = Ticket.changeset(@existing, %{title: "Printer is now merely warm"})

      assert changeset.valid?
      assert Changeset.get_change(changeset, :slug) == nil
      assert Changeset.get_field(changeset, :slug) == "old-ticket-483920"
    end

    test "an explicit non-blank slug wins" do
      changeset = Ticket.changeset(@existing, %{slug: "custom-slug"})

      assert changeset.valid?
      assert Changeset.get_change(changeset, :slug) == "custom-slug"
    end
  end

  describe "generation is required" do
    test "a punctuation-only title fails on :slug instead of inserting nil" do
      changeset =
        Ticket.changeset(%Ticket{}, %{
          user_uuid: "018e3c4a-1111-7890-abcd-ef1234567890",
          title: "!!!",
          description: "Nothing romanizable.",
          status: "open"
        })

      refute changeset.valid?
      assert :slug in Keyword.keys(changeset.errors)
      assert Changeset.get_change(changeset, :slug) == nil
    end
  end
end
