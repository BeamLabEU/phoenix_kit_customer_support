defmodule PhoenixKitCustomerSupport.GuestRequests do
  @moduledoc """
  Anonymous (guest) support requests: a visitor without an account files a
  ticket with a name and an email, and follows it through an emailed,
  expiring signed link.

  **Off by default.** The admin setting `customer_support_allow_anonymous_requests`
  (Settings → Customer Support) turns the public pages on; with it off they
  answer "not available" and `submit/2` refuses with `:disabled`.

  ## Flow

    1. `/support/request` (`Web.GuestNew`) → `submit/2`: honeypot, the
       host's optional check, rate limit, then a ticket with no `user_uuid`,
       `guest_name` / `guest_email` set and `guest_verified_at` nil. The
       guest gets an email with a link to the request.
    2. Until that link is opened the request is **unverified** and hidden
       from staff lists and counts (`PhoenixKitCustomerSupport.list_tickets/1`
       takes `include_unverified_guests: true` to see them). Opening it
       (`verify/1`) stamps `guest_verified_at` and announces the ticket to
       staff like any new ticket.
    3. `/support/requests/:token` (`Web.GuestTicket`) shows the request and
       its public comments, and takes replies (`reply/3`) while the ticket
       is not closed. Internal notes are never shown.
    4. Every public staff reply mails the guest a fresh link
       (`notify_reply/2`), and `resend_links/2` mails links to every open
       request of an address, so an expired link is never a dead end.

  ## Links

  A link is a `Phoenix.Token` over the ticket uuid and a hash of the
  guest's email (never the email itself: the token is signed, not
  encrypted). It expires after `:guest_link_max_age` seconds (default 30
  days):

      config :phoenix_kit_customer_support, guest_link_max_age: 14 * 24 * 3600

  ## Spam controls

    * **Honeypot:** the form carries a visually hidden `website` field. A
      submission that fills it gets the normal "check your email" answer and
      nothing is stored or sent.
    * **Rate limit:** `PhoenixKitCustomerSupport.RateLimit` (per email and
      per peer address, per hour).
    * **Host check (captcha hook):** `config :phoenix_kit_customer_support,
      guest_request_check: {Mod, :fun}` — called as `fun(params, context)`
      (`context` has `:action` and `:peer_ip`) before anything is stored;
      return `:ok` or `{:error, reason}`. A failing hook (raise, exit, any
      other value) refuses the request.
  """

  import Ecto.Query, warn: false

  require Logger

  alias PhoenixKit.Settings
  alias PhoenixKitCustomerSupport.Events
  alias PhoenixKitCustomerSupport.GuestNotifier
  alias PhoenixKitCustomerSupport.RateLimit
  alias PhoenixKitCustomerSupport.Ticket
  alias PhoenixKitCustomerSupport.TicketComment
  alias PhoenixKitCustomerSupport.TicketStatusHistory
  alias Plug.Crypto.KeyGenerator

  @setting "customer_support_allow_anonymous_requests"
  @token_salt "phoenix_kit_customer_support.guest_ticket"
  @email_tag_salt "phoenix_kit_customer_support.guest_email_tag"
  @default_max_age 30 * 24 * 60 * 60
  @honeypot "website"

  @type submit_error ::
          :disabled | :rate_limited | :rejected | Ecto.Changeset.t()

  @doc "The settings key that turns guest requests on."
  def setting_key, do: @setting

  @doc "The name of the honeypot form field."
  def honeypot_field, do: @honeypot

  @doc """
  Whether anonymous requests are accepted: the module is enabled and the
  `customer_support_allow_anonymous_requests` setting is on (default off).
  """
  @spec enabled?() :: boolean()
  def enabled? do
    PhoenixKitCustomerSupport.enabled?() and Settings.get_boolean_setting(@setting, false)
  rescue
    _ -> false
  catch
    :exit, _ -> false
  end

  @doc "Link lifetime in seconds (`:guest_link_max_age`, default 30 days)."
  @spec link_max_age() :: pos_integer()
  def link_max_age do
    case Application.get_env(:phoenix_kit_customer_support, :guest_link_max_age) do
      n when is_integer(n) and n > 0 -> n
      _ -> @default_max_age
    end
  end

  # ── Filing a request ──────────────────────────────────────────────────

  @doc """
  Files a guest request from form params (`"guest_name"`, `"guest_email"`,
  `"title"`, `"description"`, and the honeypot field).

  Options: `:peer_ip` (rate limit), `:locale` (stored for the guest's
  emails; defaults to the current Gettext locale).

  Returns `{:ok, ticket}` — the guest has been mailed a link —
  `{:ok, :discarded}` for a honeypot hit (show the same answer as success),
  or `{:error, :disabled | :rate_limited | :rejected | changeset}`.
  """
  @spec submit(map(), keyword()) :: {:ok, Ticket.t() | :discarded} | {:error, submit_error()}
  def submit(params, opts \\ []) when is_map(params) do
    peer_ip = Keyword.get(opts, :peer_ip)

    cond do
      not enabled?() ->
        {:error, :disabled}

      honeypot_filled?(params) ->
        {:ok, :discarded}

      true ->
        # Validated before the rate limit counts it: junk carrying someone's
        # address must not use up that address's allowance.
        with :ok <- host_check(params, :request, peer_ip),
             :ok <- validate_request(params),
             :ok <- RateLimit.check(:request, params["guest_email"], peer_ip) do
          create(params, Keyword.get_lazy(opts, :locale, &current_locale/0))
        end
    end
  end

  @doc "Empty changeset for the guest form."
  @spec change_request(map()) :: Ecto.Changeset.t()
  def change_request(params \\ %{}) do
    Ticket.guest_changeset(%Ticket{}, Map.put(params, "status", "open"))
  end

  defp validate_request(params) do
    case change_request(params) do
      %Ecto.Changeset{valid?: true} -> :ok
      changeset -> {:error, %{changeset | action: :insert}}
    end
  end

  defp create(params, locale) do
    attrs =
      params
      |> Map.take(["guest_name", "guest_email", "title", "description"])
      |> Map.put("status", "open")
      |> Map.put("metadata", %{"guest_locale" => locale})

    repo().transaction(fn ->
      case %Ticket{} |> Ticket.guest_changeset(attrs) |> repo().insert() do
        {:ok, ticket} ->
          # No user to attribute it to: `changed_by_uuid` stays nil (the
          # column is nullable since V1; the changeset requires it for staff).
          repo().insert!(%TicketStatusHistory{
            ticket_uuid: ticket.uuid,
            from_status: nil,
            to_status: "open"
          })

          ticket

        {:error, changeset} ->
          repo().rollback(changeset)
      end
    end)
    |> case do
      {:ok, ticket} ->
        GuestNotifier.request_received(ticket, access_url(ticket))
        {:ok, ticket}

      error ->
        error
    end
  end

  # ── Links ─────────────────────────────────────────────────────────────

  @doc "A signed access token for the guest's request."
  @spec access_token(Ticket.t()) :: String.t()
  def access_token(%Ticket{uuid: uuid, guest_email: email}) when is_binary(email) do
    Phoenix.Token.sign(token_endpoint(), @token_salt, %{"t" => uuid, "e" => email_tag(email)})
  end

  @doc "The full URL of the guest's request page."
  @spec access_url(Ticket.t()) :: String.t()
  def access_url(%Ticket{} = ticket),
    do: PhoenixKitCustomerSupport.Paths.guest_ticket_url(access_token(ticket))

  @doc """
  Resolves a token to its guest ticket. `{:ok, ticket}`, or `{:error,
  :expired}` / `{:error, :invalid}` (bad signature, unknown ticket, a ticket
  that is no longer a guest's, or a changed guest email).
  """
  @spec ticket_from_token(String.t() | nil) :: {:ok, Ticket.t()} | {:error, :expired | :invalid}
  def ticket_from_token(token) when is_binary(token) do
    case Phoenix.Token.verify(token_endpoint(), @token_salt, token, max_age: link_max_age()) do
      {:ok, %{"t" => uuid, "e" => tag}} ->
        with {:ok, uuid} <- Ecto.UUID.cast(uuid),
             %Ticket{} = ticket <- repo().get(Ticket, uuid),
             true <- Ticket.guest?(ticket),
             true <- Plug.Crypto.secure_compare(email_tag(ticket.guest_email), tag) do
          {:ok, ticket}
        else
          _ -> {:error, :invalid}
        end

      {:error, :expired} ->
        {:error, :expired}

      _ ->
        {:error, :invalid}
    end
  end

  def ticket_from_token(_), do: {:error, :invalid}

  # ── Verification ──────────────────────────────────────────────────────

  @doc """
  Marks the guest's email verified (the link was opened). Idempotent: a
  verified ticket is returned as is. The first verification announces the
  ticket to staff (`Events.broadcast_ticket_created/1`).
  """
  @spec verify(Ticket.t()) :: {:ok, Ticket.t()} | {:error, term()}
  def verify(%Ticket{guest_verified_at: %DateTime{}} = ticket), do: {:ok, ticket}

  def verify(%Ticket{} = ticket) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {count, _} =
      from(t in Ticket, where: t.uuid == ^ticket.uuid and is_nil(t.guest_verified_at))
      |> repo().update_all(set: [guest_verified_at: now])

    # Preloaded like the staff list's own rows: the List page prepends the
    # broadcast ticket and reads `ticket.user` / `ticket.assigned_to`.
    verified =
      case repo().get(Ticket, ticket.uuid) do
        nil -> nil
        found -> repo().preload(found, [:user, :assigned_to])
      end

    # Only the request that flipped it announces it.
    if count == 1 and verified, do: Events.broadcast_ticket_created(verified)

    if verified, do: {:ok, verified}, else: {:error, :not_found}
  end

  # ── Replies ───────────────────────────────────────────────────────────

  @doc """
  Adds the guest's public reply. Refused on a closed ticket
  (`{:error, :closed}`), when guest requests are off, over the rate limit,
  or by the host check.
  """
  @spec reply(Ticket.t(), map(), keyword()) ::
          {:ok, TicketComment.t()}
          | {:error,
             :disabled
             | :invalid
             | :expired
             | :closed
             | :rate_limited
             | :rejected
             | Ecto.Changeset.t()}
  def reply(ticket, params, opts \\ [])

  # From the guest page: the link is re-checked on every reply (its age, the
  # guest's email, the ticket still being a guest's), so a page left open
  # past `link_max_age` or after the ticket moved stops taking replies.
  def reply(%Ticket{} = ticket, params, opts) when is_list(opts) do
    case Keyword.fetch(opts, :token) do
      {:ok, token} ->
        case ticket_from_token(token) do
          {:ok, %Ticket{uuid: uuid} = current} when uuid == ticket.uuid ->
            do_reply(current, params, opts)

          {:ok, _other} ->
            {:error, :invalid}

          {:error, reason} ->
            {:error, reason}
        end

      :error ->
        do_reply(ticket, params, opts)
    end
  end

  defp do_reply(ticket, params, opts) do
    peer_ip = Keyword.get(opts, :peer_ip)

    cond do
      not enabled?() ->
        {:error, :disabled}

      # No longer a guest's (moved to an account): the link no longer
      # speaks for it, even on a page opened before the move.
      not Ticket.guest?(ticket) ->
        {:error, :invalid}

      not Ticket.can_comment?(ticket) ->
        {:error, :closed}

      honeypot_filled?(params) ->
        {:error, :rejected}

      true ->
        with :ok <- host_check(params, :reply, peer_ip),
             :ok <- RateLimit.check(:reply, ticket.guest_email, peer_ip) do
          insert_reply(ticket, params)
        end
    end
  end

  # The status check and the insert happen under the ticket's row lock, so a
  # close (or a move to an account) that commits first is always seen: no
  # reply lands on a ticket closed a moment earlier.
  defp insert_reply(ticket, params) do
    repo().transaction(fn ->
      locked = repo().one(from(t in Ticket, where: t.uuid == ^ticket.uuid, lock: "FOR UPDATE"))

      cond do
        is_nil(locked) or not Ticket.guest?(locked) -> repo().rollback(:invalid)
        not Ticket.can_comment?(locked) -> repo().rollback(:closed)
        true -> :ok
      end

      case %TicketComment{}
           |> TicketComment.guest_changeset(%{
             "ticket_uuid" => ticket.uuid,
             "content" => params["content"]
           })
           |> repo().insert() do
        {:ok, comment} ->
          from(t in Ticket, where: t.uuid == ^ticket.uuid)
          |> repo().update_all(inc: [comment_count: 1])

          Events.broadcast_comment_created(comment, repo().get(Ticket, ticket.uuid))
          comment

        {:error, changeset} ->
          repo().rollback(changeset)
      end
    end)
  end

  @doc "Public comments of a guest ticket, oldest first, with authors."
  @spec list_comments(Ticket.t()) :: [TicketComment.t()]
  def list_comments(%Ticket{uuid: uuid}) do
    from(c in TicketComment,
      where: c.ticket_uuid == ^uuid and c.is_internal == false,
      order_by: [asc: c.inserted_at],
      preload: [:user]
    )
    |> repo().all()
  end

  # ── Mail ──────────────────────────────────────────────────────────────

  @doc false
  # Called by `PhoenixKitCustomerSupport.create_comment/3` after a public
  # comment from an account lands on a guest ticket. Best-effort.
  @spec notify_reply(Ticket.t(), TicketComment.t()) :: :ok | :error
  def notify_reply(%Ticket{} = ticket, %TicketComment{} = comment) do
    if Ticket.guest?(ticket) and not comment.is_internal and not is_nil(comment.user_uuid),
      do: GuestNotifier.reply_posted(ticket, access_url(ticket)),
      else: :ok
  end

  @doc """
  Mails `email` a fresh link to each of its verified-or-not guest requests
  that is not closed. Always answers `:ok` for an address with no requests
  (never reveals whether one exists); rate limited like a request.
  """
  @spec resend_links(String.t(), keyword()) ::
          :ok | {:error, :disabled | :rate_limited | :rejected}
  def resend_links(email, opts \\ []) when is_binary(email) do
    peer_ip = Keyword.get(opts, :peer_ip)
    email = email |> String.trim() |> String.downcase()

    cond do
      not enabled?() ->
        {:error, :disabled}

      honeypot_filled?(Keyword.get(opts, :params, %{})) ->
        :ok

      true ->
        with :ok <- host_check(%{"guest_email" => email}, :resend, peer_ip),
             :ok <- RateLimit.check(:resend, email, peer_ip) do
          tickets =
            from(t in Ticket,
              where:
                is_nil(t.user_uuid) and fragment("lower(?)", t.guest_email) == ^email and
                  t.status != "closed",
              order_by: [desc: t.inserted_at],
              limit: 20
            )
            |> repo().all()

          if tickets != [],
            do: GuestNotifier.links(email, Enum.map(tickets, &{&1, access_url(&1)}))

          :ok
        end
    end
  end

  # ── internals ─────────────────────────────────────────────────────────

  defp honeypot_filled?(params) do
    case Map.get(params, @honeypot) do
      value when is_binary(value) -> String.trim(value) != ""
      nil -> false
      _ -> true
    end
  end

  defp host_check(params, action, peer_ip) do
    case Application.get_env(:phoenix_kit_customer_support, :guest_request_check) do
      nil ->
        :ok

      {mod, fun} when is_atom(mod) and is_atom(fun) ->
        run_host_check(mod, fun, params, %{action: action, peer_ip: peer_ip})

      other ->
        Logger.warning("[CustomerSupport] invalid :guest_request_check #{inspect(other)}")
        {:error, :rejected}
    end
  end

  defp run_host_check(mod, fun, params, context) do
    case apply(mod, fun, [params, context]) do
      :ok -> :ok
      _ -> {:error, :rejected}
    end
  rescue
    e ->
      Logger.warning("[CustomerSupport] guest_request_check raised: #{Exception.message(e)}")
      {:error, :rejected}
  catch
    kind, reason ->
      Logger.warning("[CustomerSupport] guest_request_check #{kind}: #{inspect(reason)}")
      {:error, :rejected}
  end

  # Keyed (HMAC with a key derived from the endpoint's `secret_key_base`):
  # the token is signed, not encrypted, so an unkeyed hash would let anyone
  # holding a link confirm a guessed address.
  defp email_tag(email) do
    :crypto.mac(:hmac, :sha256, email_tag_key(), String.downcase(email))
    |> binary_part(0, 12)
    |> Base.url_encode64(padding: false)
  end

  defp email_tag_key do
    token_endpoint().config(:secret_key_base)
    |> KeyGenerator.generate(@email_tag_salt, length: 32, cache: Plug.Crypto.Keys)
  end

  defp current_locale, do: Gettext.get_locale(PhoenixKitCustomerSupport.Gettext)

  # Explicit `config :phoenix_kit, endpoint:` wins (tests set it); a host
  # app is found through core's parent-endpoint resolution. Core's own
  # endpoint is compiled but not running in a host, so it is the last resort.
  defp token_endpoint do
    case PhoenixKit.Config.get(:endpoint) do
      {:ok, endpoint} ->
        endpoint

      _ ->
        case PhoenixKit.Config.get_parent_endpoint() do
          {:ok, endpoint} -> endpoint
          :error -> PhoenixKitWeb.Endpoint
        end
    end
  end

  defp repo, do: PhoenixKit.RepoHelper.repo()
end
