defmodule StarterKit.Repo do
  @moduledoc """
  The Ecto repository, with a tenant guard.

  A query whose root source is a tenant schema (a schema declared with
  `use StarterKit.Schema, tenant: true`) must say which organization it runs for:

      Repo.all(query, org_id: scope.organization.id)   # adds WHERE organization_id = ^org_id
      Repo.all(query, skip_org_id: true)               # deliberate cross-tenant read (admin, "my memberships")

  Without one of the two options the query raises `StarterKit.Repo.TenantError`.
  See docs/ARCHITECTURE.md §3.
  """

  use Boundary, top_level?: true, deps: [], exports: []

  use Ecto.Repo,
    otp_app: :starter_kit,
    adapter: Ecto.Adapters.Postgres

  require Ecto.Query

  defmodule TenantError do
    @moduledoc "Raised when a tenant query runs without `org_id:` or `skip_org_id:`."
    defexception [:message]
  end

  @doc "Escapes literal search text for a SQL LIKE pattern."
  def escape_like(text),
    do:
      text
      |> String.replace("\\", "\\\\")
      |> String.replace("%", "\\%")
      |> String.replace("_", "\\_")

  @max_per_page 100

  @doc """
  Returns one page of `query`: `%{entries, page, per_page, total, total_pages}`.
  `page` is clamped to 1.., `per_page` to 1..#{@max_per_page}. `opts` go to the Repo
  (pass `org_id:` / `skip_org_id:` for tenant schemas).
  """
  def paginate(query, params \\ %{}, opts \\ []) do
    per_page = params |> fetch_int("per_page", 25) |> max(1) |> min(@max_per_page)
    page = params |> fetch_int("page", 1) |> max(1) |> min(1_000_000)

    total =
      query
      |> Ecto.Query.exclude(:order_by)
      |> Ecto.Query.exclude(:select)
      |> Ecto.Query.select([row], row.id)
      |> Ecto.Query.subquery()
      |> then(&Ecto.Query.from(row in &1, select: count()))
      |> one(opts)

    entries =
      query
      |> Ecto.Query.limit(^per_page)
      |> Ecto.Query.offset(^((page - 1) * per_page))
      |> all(opts)

    %{
      entries: entries,
      page: page,
      per_page: per_page,
      total: total,
      total_pages: max(1, div(total + per_page - 1, per_page))
    }
  end

  defp fetch_int(params, key, default) do
    case params |> Map.get(key) |> to_string() |> Integer.parse() do
      {value, ""} -> value
      _ -> default
    end
  end

  @impl true
  def prepare_query(_operation, query, opts) do
    cond do
      opts[:skip_org_id] || opts[:schema_migration] ->
        {query, opts}

      not tenant_query?(query) ->
        {query, opts}

      org_id = opts[:org_id] ->
        {Ecto.Query.where(query, organization_id: ^org_id), opts}

      true ->
        raise TenantError,
          message:
            "query on tenant schema #{inspect(root_schema(query))} needs org_id: or skip_org_id: — see docs/ARCHITECTURE.md §3"
    end
  end

  defp tenant_query?(query) do
    case root_schema(query) do
      nil -> false
      schema -> function_exported?(schema, :__tenant__, 0) and schema.__tenant__()
    end
  end

  defp root_schema(%Ecto.Query{from: %{source: {_table, schema}}}) when is_atom(schema), do: schema
  defp root_schema(_), do: nil
end
