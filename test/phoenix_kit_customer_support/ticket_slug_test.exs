defmodule PhoenixKitCustomerSupport.TicketSlugTest do
  @moduledoc """
  Ticket slugs after adopting core's `PhoenixKit.Utils.Slug.put_slug/3`.

  The two local functions it replaced had three defects between them: the
  generator keyed on `get_change(:slug)`, so every status transition
  regenerated the slug; the slugify appended the last six digits of the
  millisecond clock, so each regeneration produced a NEW value — a ticket's
  URL moved on every touch, and the suffix cycles every ~16.7 minutes so it
  never guaranteed uniqueness; and it stripped non-ASCII, so a Cyrillic
  title slugged to a bare timestamp.

  Exact transliteration output is deliberately not pinned — asserting
  version-dependent romanization is how phoenix_kit_dashboards#5 merged red.
  """
  use PhoenixKitCustomerSupport.DataCase, async: true

  alias Ecto.Changeset
  alias PhoenixKitCustomerSupport.Ticket

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

  defp ticket!(user, attrs \\ %{}) do
    %Ticket{}
    |> Ticket.changeset(
      Map.merge(
        %{
          user_uuid: user.uuid,
          title: "Printer on fire",
          description: "It is genuinely on fire.",
          status: "open"
        },
        attrs
      )
    )
    |> Repo.insert!()
  end

  describe "the URL stops moving" do
    test "a status transition keeps the slug" do
      # The headline bug: get_change(:slug) is nil on a status-only save, so
      # the old code regenerated — with a fresh timestamp, so a NEW slug on
      # every single touch.
      ticket = ticket!(user!())

      {:ok, updated} =
        ticket |> Ticket.changeset(%{status: "in_progress"}) |> Repo.update()

      assert updated.slug == ticket.slug
    end

    test "an existing timestamped slug survives any edit" do
      user = user!()

      legacy =
        %Ticket{}
        |> Ticket.changeset(%{
          user_uuid: user.uuid,
          title: "Old ticket",
          description: "From before the fix.",
          status: "open",
          slug: "old-ticket-483920"
        })
        |> Repo.insert!()

      {:ok, updated} =
        legacy |> Ticket.changeset(%{description: "edited"}) |> Repo.update()

      assert updated.slug == "old-ticket-483920"
    end
  end

  describe "generation" do
    test "a new ticket gets a clean title slug, no timestamp" do
      ticket = ticket!(user!())

      assert ticket.slug == "printer-on-fire"
    end

    test "a Cyrillic title romanizes instead of slugging to a bare timestamp" do
      ticket = ticket!(user!(), %{title: "Принтер горит"})

      assert is_binary(ticket.slug) and ticket.slug != ""
      assert ticket.slug =~ ~r/^[a-z0-9-]+$/
      refute ticket.slug =~ ~r/^\d+$/
    end

    test "a title collision suffixes -2 against the now-unique index" do
      user = user!()
      first = ticket!(user)
      second = ticket!(user)

      assert first.slug == "printer-on-fire"
      assert second.slug == "printer-on-fire-2"
    end
  end
end
