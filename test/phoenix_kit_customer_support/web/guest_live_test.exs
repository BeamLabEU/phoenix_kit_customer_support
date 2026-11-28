defmodule PhoenixKitCustomerSupport.Web.GuestLiveTest do
  use PhoenixKitCustomerSupport.LiveCase, async: false

  import Swoosh.TestAssertions

  alias PhoenixKit.Settings
  alias PhoenixKitCustomerSupport.GuestRequests
  alias PhoenixKitCustomerSupport.Ticket

  defp enable do
    {:ok, _} = Settings.update_boolean_setting("customer_support_enabled", true)
    {:ok, _} = Settings.update_boolean_setting(GuestRequests.setting_key(), true)
  end

  defp guest_ticket do
    n = System.unique_integer([:positive])

    {:ok, ticket} =
      GuestRequests.submit(%{
        "guest_name" => "Guest #{n}",
        "guest_email" => "g#{n}@example.com",
        "title" => "Help #{n}",
        "description" => "Details"
      })

    ticket
  end

  test "the form says not available while the setting is off", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/support/request")
    assert has_element?(view, "#guest-request-disabled")
    refute has_element?(view, "#guest-request-form")
  end

  test "a guest files a request through the form", %{conn: conn} do
    enable()
    {:ok, view, _html} = live(conn, "/support/request")
    assert has_element?(view, "#guest-request-form input[name='request[website]']")

    view
    |> form("#guest-request-form",
      request: %{
        guest_name: "Jaan",
        guest_email: "jaan@example.com",
        title: "Broken link",
        description: "The download link 404s."
      }
    )
    |> render_submit()

    assert has_element?(view, "#guest-request-sent")

    assert %Ticket{guest_name: "Jaan", user_uuid: nil} =
             Repo.get_by!(Ticket, guest_email: "jaan@example.com")

    assert_email_sent()
  end

  test "an invalid form shows field errors", %{conn: conn} do
    enable()
    {:ok, view, _html} = live(conn, "/support/request")

    html =
      view
      |> form("#guest-request-form", request: %{guest_email: "nope"})
      |> render_submit()

    assert html =~ "guest-request-form"
    refute has_element?(view, "#guest-request-sent")
  end

  test "opening the link verifies, shows the request and takes a reply", %{conn: conn} do
    enable()
    ticket = guest_ticket()
    token = GuestRequests.access_token(ticket)

    {:ok, view, _html} = live(conn, "/support/requests/#{token}")
    assert has_element?(view, "#guest-ticket", ticket.title)
    assert %DateTime{} = Repo.get!(Ticket, ticket.uuid).guest_verified_at

    view |> form("#guest-reply-form", reply: %{content: "Thanks!"}) |> render_submit()
    assert has_element?(view, "#guest-ticket-comments", "Thanks!")
  end

  test "an open page stops showing the ticket once it moves to an account", %{conn: conn} do
    enable()
    ticket = guest_ticket()
    {:ok, view, _html} = live(conn, "/support/requests/#{GuestRequests.access_token(ticket)}")
    assert has_element?(view, "#guest-ticket")

    n = System.unique_integer([:positive])

    user =
      Repo.insert!(%PhoenixKit.Users.Auth.User{
        email: "owner#{n}@example.com",
        username: "owner_#{n}",
        hashed_password: "$2b$12$notarealhashjustenoughtosatisfythecolumn",
        is_active: true
      })

    moved = ticket |> Ecto.Changeset.change(user_uuid: user.uuid) |> Repo.update!()
    assert {:error, :invalid} = GuestRequests.reply(moved, %{"content" => "still here?"})

    send(view.pid, {:ticket_updated, moved})
    assert has_element?(view, "#guest-ticket-link-error")
    refute has_element?(view, "#guest-ticket")
  end

  test "a connected page checks the email on each update", %{conn: conn} do
    enable()
    ticket = guest_ticket()
    {:ok, view, _} = live(conn, "/support/requests/#{GuestRequests.access_token(ticket)}")

    updated =
      ticket |> Ecto.Changeset.change(guest_email: "changed@example.com") |> Repo.update!()

    send(view.pid, {:ticket_updated, updated})
    assert has_element?(view, "#guest-ticket-link-error")
    refute has_element?(view, "#guest-ticket")
  end

  test "an expired link stops receiving updates on an open page", %{conn: conn} do
    enable()
    ticket = guest_ticket()
    endpoint = PhoenixKitCustomerSupport.Test.Endpoint
    salt = "phoenix_kit_customer_support.guest_ticket"

    {:ok, payload} =
      Phoenix.Token.verify(endpoint, salt, GuestRequests.access_token(ticket), max_age: 60)

    token =
      Phoenix.Token.sign(endpoint, salt, payload, signed_at: System.system_time(:second) - 120)

    {:ok, view, _} = live(conn, "/support/requests/#{token}")

    previous = Application.fetch_env(:phoenix_kit_customer_support, :guest_link_max_age)

    on_exit(fn ->
      case previous do
        {:ok, age} -> Application.put_env(:phoenix_kit_customer_support, :guest_link_max_age, age)
        :error -> Application.delete_env(:phoenix_kit_customer_support, :guest_link_max_age)
      end
    end)

    Application.put_env(:phoenix_kit_customer_support, :guest_link_max_age, 60)
    send(view.pid, {:ticket_updated, ticket})
    assert has_element?(view, "#guest-ticket-link-error", "expired")
    refute has_element?(view, "#guest-ticket")
  end

  test "disabling guest requests hides an open ticket on its next update", %{conn: conn} do
    enable()
    ticket = guest_ticket()
    {:ok, view, _} = live(conn, "/support/requests/#{GuestRequests.access_token(ticket)}")
    {:ok, _} = Settings.update_boolean_setting(GuestRequests.setting_key(), false)
    send(view.pid, {:ticket_updated, ticket})
    assert has_element?(view, "#guest-ticket-link-error", "not available")
    refute has_element?(view, "#guest-ticket")
  end

  test "a bad link shows a notice", %{conn: conn} do
    enable()
    {:ok, view, _html} = live(conn, "/support/requests/garbage")
    assert has_element?(view, "#guest-ticket-link-error")
    refute has_element?(view, "#guest-ticket")
  end
end
