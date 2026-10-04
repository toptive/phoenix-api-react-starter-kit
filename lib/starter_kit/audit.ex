defmodule StarterKit.Audit do
  @moduledoc """
  The append-only audit log (SOC 2): who did what to which record, and whether a
  superadmin was impersonating at the time.

      Audit.record("organization.member_removed", scope: scope, subject: membership, metadata: %{…})

  Options: `:scope` (fills actor, impersonator, organization) or `:actor`, plus
  `:subject` (any struct with an `id`), `:metadata`, `:ip_address`, `:organization_id`.
  Without `:ip_address`, the event takes the visitor IP of the current request
  (`put_request_ip/1`, set by `StarterKitWeb.Plugs.ClientIp`); jobs have none.
  """

  use Boundary,
    top_level?: true,
    deps: [StarterKit.Repo, StarterKit.Schema, StarterKit.Policy],
    exports: [AuditEvent, AuditEventPolicy]

  import Ecto.Query

  alias StarterKit.Audit.AuditEvent
  alias StarterKit.Repo

  @request_ip {__MODULE__, :request_ip}

  @doc """
  Sets the visitor IP for events recorded by this process (one request). Every request
  sets it again, so a reused connection process never keeps the previous visitor's IP.
  """
  def put_request_ip(ip) when is_binary(ip) or is_nil(ip) do
    Process.put(@request_ip, ip)
    :ok
  end

  @doc "Records one event. Never raises: a failed write is logged, not propagated."
  def record(action, opts \\ []) when is_binary(action) do
    scope = opts[:scope]
    subject = opts[:subject]

    attrs = %{
      action: action,
      actor_id: id_of(opts[:actor] || (scope && scope.user)),
      impersonator_id: id_of(scope && scope.impersonator),
      organization_id: opts[:organization_id] || id_of(scope && scope.organization),
      subject_type: subject && subject.__struct__ |> Module.split() |> List.last(),
      subject_id: id_of(subject),
      metadata: opts |> Keyword.get(:metadata, %{}) |> stringify(),
      ip_address: ip_address(opts)
    }

    case Repo.insert(struct(AuditEvent, attrs)) do
      {:ok, event} ->
        {:ok, event}

      {:error, changeset} ->
        require Logger
        Logger.error("audit event #{action} not recorded: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  @doc """
  Lists events for the admin area, newest first. `q` is a record id (subject or actor)
  or part of an action name.
  """
  def list_events(_scope, params) do
    q = params |> Map.get("q", "") |> String.trim()
    query = from e in AuditEvent, order_by: [desc: e.inserted_at]

    query =
      case Ecto.UUID.cast(q) do
        {:ok, id} -> where(query, [e], e.subject_id == ^id or e.actor_id == ^id)
        :error when q != "" -> where(query, [e], ilike(e.action, ^"%#{Repo.escape_like(q)}%"))
        :error -> query
      end

    page = Repo.paginate(query, params)
    %{page | entries: with_actor_emails(page.entries)}
  end

  # Schemaless read of users(id, email): Audit sits below Accounts and must not call it.
  defp with_actor_emails(events) do
    ids =
      events
      |> Enum.map(& &1.actor_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.map(&Ecto.UUID.dump!/1)

    emails =
      from(u in "users", where: u.id in ^ids, select: {u.id, u.email})
      |> Repo.all()
      |> Map.new(fn {id, email} -> {Ecto.UUID.load!(id), email} end)

    Enum.map(events, &%{&1 | actor_email: Map.get(emails, &1.actor_id)})
  end

  defp ip_address(opts), do: Keyword.get_lazy(opts, :ip_address, fn -> Process.get(@request_ip) end)

  defp id_of(%{id: id}), do: id
  defp id_of(_), do: nil

  defp stringify(map) when is_map(map) do
    Map.new(map, fn {k, v} ->
      {to_string(k), if(is_atom(v) and v not in [nil, true, false], do: to_string(v), else: v)}
    end)
  end
end
