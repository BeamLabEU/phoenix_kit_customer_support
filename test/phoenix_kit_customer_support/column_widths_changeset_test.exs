defmodule PhoenixKitCustomerSupport.ColumnWidthsChangesetTest do
  @moduledoc """
  `column_widths/0` is the single width authority for both the V1 DDL
  (`migrations_test.exs` pins that side) and the changesets. This pins the
  changeset side: a value one past the declared width is a changeset error,
  never a `string_data_right_truncation` raised by Postgres. Changeset-only —
  the existing-slug case never reaches `put_slug/3`'s uniqueness probe, so no
  database is needed.
  """
  use ExUnit.Case, async: true

  alias PhoenixKitCustomerSupport.Ticket
  alias PhoenixKitCustomerSupport.TicketStatusHistory

  @existing %Ticket{
    uuid: "018e3c4a-9f6b-7890-abcd-ef1234567890",
    user_uuid: "018e3c4a-1111-7890-abcd-ef1234567890",
    title: "Existing ticket",
    description: "Already saved.",
    status: "open",
    slug: "existing-ticket"
  }

  @history_attrs %{
    ticket_uuid: "018e3c4a-9f6b-7890-abcd-ef1234567890",
    changed_by_uuid: "018e3c4a-1111-7890-abcd-ef1234567890",
    from_status: "open",
    to_status: "closed"
  }

  describe "Ticket.changeset/2 validates against Ticket.column_widths/0" do
    for field <- [:title, :slug] do
      test "#{field} at the width is accepted, one past it is rejected" do
        field = unquote(field)
        width = Map.fetch!(Ticket.column_widths(), field)

        at_width = Ticket.changeset(@existing, %{field => String.duplicate("a", width)})
        assert at_width.valid?

        past = Ticket.changeset(@existing, %{field => String.duplicate("a", width + 1)})
        refute past.valid?
        assert {_, opts} = past.errors[field]
        assert opts[:count] == width
      end
    end
  end

  describe "TicketStatusHistory.changeset/2 validates against its column_widths/0" do
    for field <- [:from_status, :to_status] do
      test "#{field} at the width is accepted, one past it is rejected" do
        field = unquote(field)
        width = Map.fetch!(TicketStatusHistory.column_widths(), field)

        at_width =
          TicketStatusHistory.changeset(
            %TicketStatusHistory{},
            Map.put(@history_attrs, field, String.duplicate("a", width))
          )

        assert at_width.valid?

        past =
          TicketStatusHistory.changeset(
            %TicketStatusHistory{},
            Map.put(@history_attrs, field, String.duplicate("a", width + 1))
          )

        refute past.valid?
        assert {_, opts} = past.errors[field]
        assert opts[:count] == width
      end
    end
  end
end
