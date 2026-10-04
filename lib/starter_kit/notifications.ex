defmodule StarterKit.Notifications do
  @moduledoc """
  The ONE call site for telling a person something (today: email; add in-app or push
  here as new channels).

      Notifications.notify(user, :magic_link, %{url: url})

  Every email uses ONE branded layout (`Notifications.Email`): logo header, headline,
  lead, facts, one button, notes, and a footer with the reason. Texts come from the i18n
  catalogue (`mail.<kind>.subject`, `.headline`, `.lead`, `.action`, …), rendered in the
  recipient's locale. Delivery runs in an Oban job (queue `default`), so a slow provider
  never blocks a request.

  Every kind belongs to a group:

    * `:access` — sign-in and account security (magic link, email change). Always sent.
    * `:transactional` — what the person or their organization did or bought. Always sent.
    * `:optional` — lifecycle and marketing. Sent to a user, `notify/3` adds a signed
      one-click `unsubscribe_url` and the settings `preferences_url` itself and skips a
      user with `optional_emails: false`; other recipients must pass `unsubscribe_url`. The email shows "Unsubscribe"
      (+ "Email preferences" with `preferences_url`), carries RFC 8058 `List-Unsubscribe`
      + `List-Unsubscribe-Post` headers (any Swoosh adapter) and goes through the Postmark
      broadcast stream.

  `/dev/emails` (dev only) shows every kind in every locale through `preview/2`.

  Delivery fails closed: without a working adapter (`email_available?/0`) the job waits
  and retries; outside production, `MAIL_ALLOWED_RECIPIENTS` limits who gets mail.
  """

  use Boundary,
    top_level?: true,
    deps: [StarterKit.Mailer, StarterKit.I18n],
    exports: []

  alias StarterKit.Notifications.{DeliveryWorker, Email}

  require Logger

  @kinds %{
    "magic_link" => :access,
    "email_change" => :access,
    "invitation" => :transactional,
    "renewal_notice" => :transactional,
    # News for every user: pass `title`, `summary` and `url` in the user's locale.
    "product_update" => :optional
  }

  @doc "Every notification kind (each one renders through the shared layout)."
  def kinds, do: @kinds |> Map.keys() |> Enum.sort()

  @doc "The group of `kind`: `:access`, `:transactional` or `:optional`."
  def group(kind), do: Map.fetch!(@kinds, to_string(kind))

  @doc """
  True when mail can really leave: Postmark with an API key, or the dev/test adapters
  that keep mail locally. The production fallback (the Logger adapter, no key) is false.
  Callers that only exist to send mail (sign-up, sign-in links) refuse when it is false.
  """
  def email_available? do
    config = Application.get_env(:starter_kit, StarterKit.Mailer, [])

    case config[:adapter] do
      Swoosh.Adapters.Postmark ->
        is_binary(config[:api_key]) and String.trim(config[:api_key]) != ""

      adapter ->
        adapter in [Swoosh.Adapters.Local, Swoosh.Adapters.Test]
    end
  end

  @doc """
  True when `email` may get mail. `config :starter_kit, :mail_allowed_recipients`
  (env `MAIL_ALLOWED_RECIPIENTS`: `ana@toptive.co,*@toptive.co`) limits a non-production
  deploy to these addresses; `nil` (production) allows everyone.
  """
  def recipient_allowed?(email) do
    case Application.get_env(:starter_kit, :mail_allowed_recipients) do
      nil -> true
      patterns -> Enum.any?(patterns, &matches?(String.downcase(email), String.downcase(&1)))
    end
  end

  defp matches?(email, "*@" <> domain), do: String.ends_with?(email, "@" <> domain)
  defp matches?(email, pattern), do: email == pattern

  @doc """
  Queues a notification for `recipient` (anything with email, name, locale). Optional
  mail to a user who unsubscribed is not queued: `{:ok, :opted_out}`.
  """
  def notify(recipient, kind, data \\ %{}) when is_atom(kind) do
    kind = Atom.to_string(kind)
    unless Map.has_key?(@kinds, kind), do: raise(ArgumentError, "unknown notification kind #{kind}")
    data = Map.new(data, fn {k, v} -> {to_string(k), v} end)

    if @kinds[kind] == :optional and Map.get(recipient, :optional_emails) == false do
      {:ok, :opted_out}
    else
      enqueue(recipient, kind, with_unsubscribe_url(recipient, @kinds[kind], data))
    end
  end

  defp with_unsubscribe_url(recipient, :optional, data) do
    case {data["unsubscribe_url"], recipient} do
      {url, _} when is_binary(url) ->
        data

      {_, %{id: id, email: email}} when is_binary(id) ->
        data
        |> Map.put("unsubscribe_url", unsubscribe_url(id, email))
        |> Map.put("unsubscribe_page_url", unsubscribe_page_url(id, email))
        |> Map.put_new("preferences_url", preferences_url())

      _ ->
        raise ArgumentError, "optional notification to a non-user needs an unsubscribe_url"
    end
  end

  defp with_unsubscribe_url(_recipient, _group, data), do: data

  @unsubscribe_salt "optional email opt-out"

  @doc """
  The one-click unsubscribe URL of a user (the List-Unsubscribe target and the footer
  link): a signed token of the user id and a hash of the address, valid with no expiry
  (old emails keep working) and only while the user keeps that address.
  """
  def unsubscribe_url(user_id, email) do
    token = Plug.Crypto.sign(secret_key_base(), @unsubscribe_salt, [user_id, email_hash(email)])

    "#{Application.fetch_env!(:starter_kit, :public_url)}/api/v1/email-subscriptions/#{token}/opt-out"
  end

  @doc "The SPA footer link; scanners can open it without unsubscribing."
  def unsubscribe_page_url(user_id, email) do
    token = Plug.Crypto.sign(secret_key_base(), @unsubscribe_salt, [user_id, email_hash(email)])
    "#{Application.fetch_env!(:starter_kit, :spa_origin)}/email-subscriptions/#{token}/opt-out"
  end

  @doc "The settings page where a signed-in user turns optional mail on or off."
  def preferences_url,
    do: "#{Application.fetch_env!(:starter_kit, :spa_origin)}/settings/email-preferences/edit"

  @doc """
  Reads an unsubscribe token: `{:ok, user_id, email_hash}` or `:error`. Compare the hash
  with `email_hash/1` of the user's current address.
  """
  def verify_unsubscribe_token(token) when is_binary(token) do
    case Plug.Crypto.verify(secret_key_base(), @unsubscribe_salt, token, max_age: :infinity) do
      {:ok, [user_id, hash]} -> {:ok, user_id, hash}
      _ -> :error
    end
  end

  @doc "The hash an unsubscribe token carries instead of the address."
  def email_hash(email),
    do:
      :crypto.hash(:sha256, String.downcase(email))
      |> binary_part(0, 16)
      |> Base.url_encode64(padding: false)

  defp secret_key_base, do: Application.fetch_env!(:starter_kit, :secret_key_base)

  defp enqueue(recipient, kind, data) do
    %{
      "recipient" => %{
        "email" => recipient.email,
        "name" => Map.get(recipient, :name) || "",
        "locale" => Map.get(recipient, :locale) || "en"
      },
      "kind" => kind,
      "data" => data
    }
    |> DeliveryWorker.new()
    |> Oban.insert()
  end

  # Every binding any kind uses, so a preview leaves no placeholder unfilled. A new kind
  # with new bindings adds them here (email_preview_test.exs fails otherwise).
  @preview_data %{
    "url" => "https://app.example.com/action",
    "inviter" => "Ana Pérez",
    "organization" => "Acme Studio",
    "plan" => "Pro",
    "date" => "2026-11-01",
    "amount" => "USD 190.00",
    "title" => "Shared folders",
    "summary" => "Share a folder with your whole team in one click.",
    "unsubscribe_url" => "https://app.example.com/email-subscriptions/preview/opt-out",
    "preferences_url" => "https://app.example.com/settings/email-preferences/edit"
  }

  @doc """
  The email `kind` would send in `locale`, built with sample data and never delivered.
  For the dev gallery (`/dev/emails`).
  """
  def preview(kind, locale) do
    kind = to_string(kind)
    recipient = %{"email" => "bo@example.com", "name" => "Bo Lind", "locale" => locale}
    Email.build(recipient, kind, @preview_data, group(kind))
  end

  @doc false
  # The delivery job. No adapter: wait an hour and try again (never a silent drop). A
  # recipient outside MAIL_ALLOWED_RECIPIENTS: the job is cancelled and logged.
  def deliver_now(%{"recipient" => %{"email" => to} = recipient, "kind" => kind, "data" => data}) do
    cond do
      not email_available?() ->
        Logger.warning("mail: no delivery adapter configured, #{kind} waits")
        {:snooze, 3600}

      not recipient_allowed?(to) ->
        domain = to |> String.split("@") |> List.last()
        Logger.warning("mail: #{kind} to @#{domain} dropped (not in MAIL_ALLOWED_RECIPIENTS)")
        {:cancel, :recipient_not_allowed}

      true ->
        email = Email.build(recipient, kind, data, group(kind))

        case StarterKit.Mailer.deliver(email) do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end
end
