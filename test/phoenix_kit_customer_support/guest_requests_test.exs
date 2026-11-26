defmodule PhoenixKitCustomerSupport.GuestRequestsTest do
  # Settings and Application env are global: not async.
  use PhoenixKitCustomerSupport.DataCase, async: false

  import Swoosh.TestAssertions

  alias PhoenixKit.Settings
  alias PhoenixKitCustomerSupport.GuestRequests
  alias PhoenixKitCustomerSupport.Ticket
  alias PhoenixKitCustomerSupport.TicketComment

  @params %{
    "guest_name" => "Mari Maasikas",
    "guest_email" => " Mari@Example.com ",
    "title" => "Cannot find my order",
    "description" => "I ordered last week and nothing arrived."
  }

  setup do
    on_exit(fn ->
      Application.delete_env(:phoenix_kit_customer_support, :guest_request_check)
      Application.delete_env(:phoenix_kit_customer_support, :guest_rate_limit)
      Application.delete_env(:phoenix_kit_customer_support, :guest_link_max_age)
    end)

    :ok
  end

  defp enable do
    {:ok, _} = Settings.update_boolean_setting("customer_support_enabled", true)
    {:ok, _} = Settings.update_boolean_setting(GuestRequests.setting_key(), true)
    :ok
  end

  defp unique_params(extra \\ %{}) do
    n = System.unique_integer([:positive])

    @params
    |> Map.put("guest_email", "guest#{n}@example.com")
    |> Map.merge(extra)
  end

  defp staff_user do
    n = System.unique_integer([:positive])

    Repo.insert!(%PhoenixKit.Users.Auth.User{
      email: "staff#{n}@example.com",
      username: "staff_#{n}",
      hashed_password: "$2b$12$notarealhashjustenoughtosatisfythecolumn",
      is_active: true
    })
  end

  describe "off by default" do
    test "the setting defaults to off and submit refuses" do
      {:ok, _} = Settings.update_boolean_setting("customer_support_enabled", true)
      refute GuestRequests.enabled?()
      assert {:error, :disabled} = GuestRequests.submit(@params)
      assert Repo.aggregate(Ticket, :count) == 0
    end

    test "the setting alone is not enough while the module is off" do
      {:ok, _} = Settings.update_boolean_setting(GuestRequests.setting_key(), true)
      {:ok, _} = Settings.update_boolean_setting("customer_support_enabled", false)
      refute GuestRequests.enabled?()
    end
  end

  describe "submit/2" do
    setup do: enable()

    test "files an unverified guest ticket, normalises the email and mails a link" do
      assert {:ok, %Ticket{} = ticket} = GuestRequests.submit(@params, locale: "et")

      assert ticket.user_uuid == nil
      assert ticket.guest_email == "mari@example.com"
      assert ticket.guest_name == "Mari Maasikas"
      assert ticket.guest_verified_at == nil
      assert ticket.status == "open"
      assert ticket.metadata["guest_locale"] == "et"

      assert_email_sent(fn email ->
        assert [{_, "mari@example.com"}] = email.to
        assert email.text_body =~ "/support/requests/"
        true
      end)
    end

    test "an unverified request is hidden from staff lists and counts until verified" do
      {:ok, ticket} = GuestRequests.submit(unique_params())

      assert PhoenixKitCustomerSupport.list_tickets() == []
      assert [_] = PhoenixKitCustomerSupport.list_tickets(include_unverified_guests: true)
      assert PhoenixKitCustomerSupport.get_stats().total == 0

      {:ok, verified} = GuestRequests.verify(ticket)
      assert %DateTime{} = verified.guest_verified_at
      assert [%{uuid: uuid}] = PhoenixKitCustomerSupport.list_tickets()
      assert uuid == ticket.uuid
      assert PhoenixKitCustomerSupport.get_stats().total == 1

      # Idempotent.
      assert {:ok, ^verified} = GuestRequests.verify(verified)
    end

    test "requires a name, a valid email, a title and a description" do
      assert {:error, %Ecto.Changeset{} = cs} =
               GuestRequests.submit(%{"guest_email" => "not-an-email"})

      errors = Map.new(cs.errors, fn {k, _} -> {k, true} end)

      assert errors[:guest_name] and errors[:guest_email] and errors[:title] and
               errors[:description]
    end

    test "a filled honeypot looks like success and stores and sends nothing" do
      params = Map.put(unique_params(), GuestRequests.honeypot_field(), "http://spam.example")
      assert {:ok, :discarded} = GuestRequests.submit(params)
      assert Repo.aggregate(Ticket, :count) == 0
      assert_no_email_sent()
    end

    test "the rate limit counts per address" do
      Application.put_env(:phoenix_kit_customer_support, :guest_rate_limit, per_address: 1)
      params = unique_params()

      assert {:ok, _} = GuestRequests.submit(params)
      assert {:error, :rate_limited} = GuestRequests.submit(params)
    end

    test "the rate limit counts per peer address" do
      Application.put_env(:phoenix_kit_customer_support, :guest_rate_limit, per_peer: 1)
      peer = {10, 0, 0, System.unique_integer([:positive]) |> rem(250)}

      assert {:ok, _} = GuestRequests.submit(unique_params(), peer_ip: peer)
      assert {:error, :rate_limited} = GuestRequests.submit(unique_params(), peer_ip: peer)
    end

    test "the peer bucket is the visitor's network: IPv4-mapped IPv6 is its IPv4, IPv6 its /64" do
      Application.put_env(:phoenix_kit_customer_support, :guest_rate_limit, per_peer: 1)
      n = System.unique_integer([:positive]) |> rem(250)

      assert {:ok, _} = GuestRequests.submit(unique_params(), peer_ip: {10, 1, 2, n})

      assert {:error, :rate_limited} =
               GuestRequests.submit(unique_params(),
                 peer_ip: {0, 0, 0, 0, 0, 65_535, 2561, 512 + n}
               )

      # Two IPv4-mapped clients of one listener are different visitors.
      assert {:ok, _} =
               GuestRequests.submit(unique_params(), peer_ip: {0, 0, 0, 0, 0, 65_535, 2562, n})

      assert {:ok, _} = GuestRequests.submit(unique_params(), peer_ip: "2001:db8:#{n}::1")

      assert {:error, :rate_limited} =
               GuestRequests.submit(unique_params(), peer_ip: "2001:db8:#{n}::ffff")
    end

    test "the host check (captcha hook) can refuse, and a crashing hook refuses" do
      Application.put_env(
        :phoenix_kit_customer_support,
        :guest_request_check,
        {__MODULE__, :deny}
      )

      assert {:error, :rejected} = GuestRequests.submit(unique_params())

      Application.put_env(
        :phoenix_kit_customer_support,
        :guest_request_check,
        {__MODULE__, :boom}
      )

      assert {:error, :rejected} = GuestRequests.submit(unique_params())

      Application.put_env(
        :phoenix_kit_customer_support,
        :guest_request_check,
        {__MODULE__, :allow}
      )

      assert {:ok, %Ticket{}} = GuestRequests.submit(unique_params())
      assert_received {:host_check, :request, %{"title" => _}}
    end
  end

  def deny(_params, _context), do: {:error, :captcha}
  def boom(_params, _context), do: raise("captcha service down")

  def allow(params, context) do
    send(self(), {:host_check, context.action, params})
    :ok
  end

  describe "links" do
    setup do: enable()

    test "a token resolves to its ticket" do
      {:ok, ticket} = GuestRequests.submit(unique_params())
      token = GuestRequests.access_token(ticket)

      assert {:ok, %Ticket{uuid: uuid}} = GuestRequests.ticket_from_token(token)
      assert uuid == ticket.uuid
      refute token =~ ticket.guest_email
    end

    test "an expired token is refused as expired" do
      {:ok, ticket} = GuestRequests.submit(unique_params())
      token = GuestRequests.access_token(ticket)

      Application.put_env(:phoenix_kit_customer_support, :guest_link_max_age, 1)
      Process.sleep(2_100)
      assert {:error, :expired} = GuestRequests.ticket_from_token(token)
    end

    test "tampered tokens, a changed guest email and non-guest tickets are invalid" do
      {:ok, ticket} = GuestRequests.submit(unique_params())
      token = GuestRequests.access_token(ticket)

      assert {:error, :invalid} = GuestRequests.ticket_from_token(token <> "x")
      assert {:error, :invalid} = GuestRequests.ticket_from_token(nil)

      ticket |> Ecto.Changeset.change(guest_email: "other@example.com") |> Repo.update!()
      assert {:error, :invalid} = GuestRequests.ticket_from_token(token)
    end
  end

  describe "replies" do
    setup do: enable()

    test "a guest reply is a public comment without a user" do
      {:ok, ticket} = GuestRequests.submit(unique_params())

      assert {:ok, %TicketComment{} = comment} =
               GuestRequests.reply(ticket, %{"content" => "Any news?"})

      assert comment.user_uuid == nil
      refute comment.is_internal
      assert Repo.get!(Ticket, ticket.uuid).comment_count == 1
      assert [%{content: "Any news?"}] = GuestRequests.list_comments(ticket)
    end

    test "a closed ticket takes no reply; an empty one is a changeset error" do
      {:ok, ticket} = GuestRequests.submit(unique_params())
      assert {:error, %Ecto.Changeset{}} = GuestRequests.reply(ticket, %{"content" => ""})

      closed = ticket |> Ecto.Changeset.change(status: "closed") |> Repo.update!()
      assert {:error, :closed} = GuestRequests.reply(closed, %{"content" => "hello"})
    end

    test "internal notes never reach the guest's comment list" do
      {:ok, ticket} = GuestRequests.submit(unique_params())
      staff = staff_user()

      {:ok, _} =
        PhoenixKitCustomerSupport.create_internal_note(ticket.uuid, staff.uuid, %{
          "content" => "secret"
        })

      assert GuestRequests.list_comments(ticket) == []
    end

    test "a staff public reply mails the guest a fresh link" do
      {:ok, ticket} = GuestRequests.submit(unique_params())
      assert_email_sent()
      staff = staff_user()

      {:ok, _} =
        PhoenixKitCustomerSupport.create_comment(ticket.uuid, staff.uuid, %{
          "content" => "Looking"
        })

      assert_email_sent(fn email ->
        assert [{_, to}] = email.to
        assert to == ticket.guest_email
        assert email.text_body =~ "/support/requests/"
        refute email.text_body =~ "Looking"
        true
      end)
    end
  end

  describe "resend_links/2" do
    setup do: enable()

    test "mails links for open requests and answers :ok for unknown addresses" do
      params = unique_params()
      {:ok, _} = GuestRequests.submit(params)
      assert_email_sent()

      assert :ok = GuestRequests.resend_links(String.upcase(params["guest_email"]))
      assert_email_sent(fn email -> email.text_body =~ "/support/requests/" end)

      assert :ok = GuestRequests.resend_links("nobody-#{System.unique_integer()}@example.com")
      assert_no_email_sent()
    end
  end
end
