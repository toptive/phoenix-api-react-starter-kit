defmodule StarterKit.Legal do
  @moduledoc """
  Legal documents (terms, privacy, cookies) stored in the database, versioned, and
  published by superadmins. Public pages show the published version; each version is
  immutable, so an acceptance always points to the exact text the user saw.
  """

  use Boundary,
    top_level?: true,
    deps: [StarterKit.Repo, StarterKit.Schema, StarterKit.Policy, StarterKit.Audit],
    exports: [LegalDocument, LegalDocumentVersion, LegalDocumentPolicy]

  import Ecto.Query

  alias StarterKit.{Audit, Repo}
  alias StarterKit.Legal.{LegalAcceptance, LegalDocument, LegalDocumentVersion}

  @doc "Document slugs."
  def slugs, do: LegalDocument.slugs()

  @doc """
  The published page for `slug` in `locale`:
  `{:ok, %{slug, title, body, version, published_at}}` or `{:error, :not_found}`.
  """
  def published_page(slug, locale) do
    query =
      from d in LegalDocument,
        where: d.slug == ^slug,
        join: v in assoc(d, :published_version),
        select: v

    case Repo.one(query) do
      %LegalDocumentVersion{} = version ->
        {:ok,
         %{
           slug: slug,
           title: LegalDocumentVersion.title_for(version, locale),
           body: LegalDocumentVersion.body_for(version, locale),
           version: version.number,
           published_at: version.published_at
         }}

      nil ->
        {:error, :not_found}
    end
  end

  @doc "The slugs that have a published version (sitemap, footer links)."
  def published_slugs do
    Repo.all(from d in LegalDocument, where: not is_nil(d.published_version_id), select: d.slug)
  end

  @doc "All documents with their versions (admin), creating missing slugs on the fly."
  def list_documents(_scope) do
    ensure_documents()

    Repo.all(
      from d in LegalDocument,
        order_by: d.slug,
        preload: [versions: ^from(v in LegalDocumentVersion, order_by: [desc: v.number])]
    )
  end

  @doc "A document by slug, with versions (admin)."
  def get_document!(_scope, slug) do
    ensure_documents()

    Repo.one!(
      from d in LegalDocument,
        where: d.slug == ^slug,
        preload: [versions: ^from(v in LegalDocumentVersion, order_by: [desc: v.number])]
    )
  end

  defp ensure_documents do
    now = DateTime.utc_now(:second)

    Repo.insert_all(
      LegalDocument,
      Enum.map(slugs(), &%{id: Ecto.UUID.generate(), slug: &1, inserted_at: now, updated_at: now}),
      on_conflict: :nothing,
      conflict_target: :slug
    )
  end

  @doc "Creates a version from a flat API request with a validated publish flag."
  def create_document_version(scope, slug, attrs) do
    document = get_document!(scope, slug)
    changeset = {%{}, %{publish: :boolean}} |> Ecto.Changeset.cast(attrs, [:publish])

    with {:ok, values} <- Ecto.Changeset.apply_action(changeset, :insert) do
      create_version(scope, document, Map.take(attrs, ["titles", "bodies", "note"]),
        publish: values[:publish] || false
      )
    end
  end

  @doc "Publishes a numbered version and returns the document."
  def publish_document_version(scope, slug, number) do
    document = get_document!(scope, slug)

    case Integer.parse(to_string(number)) do
      {number, ""} when number > 0 ->
        version = get_version!(document, number)

        with {:ok, _} <- publish_version(scope, document, version),
             do: {:ok, get_document!(scope, slug)}

      _ ->
        {:error, :not_found}
    end
  end

  @doc "A changeset for the version form."
  def change_version(attrs \\ %{}),
    do: LegalDocumentVersion.changeset(%LegalDocumentVersion{}, attrs)

  @doc """
  Adds a new version. With `publish: true` it is published in the same transaction.
  """
  def create_version(scope, %LegalDocument{} = document, attrs, opts \\ []) do
    Repo.transact(fn ->
      Repo.one!(from d in LegalDocument, where: d.id == ^document.id, lock: "FOR UPDATE")

      number =
        (Repo.one(
           from v in LegalDocumentVersion,
             where: v.legal_document_id == ^document.id,
             select: max(v.number)
         ) || 0) + 1

      with {:ok, version} <-
             %LegalDocumentVersion{
               legal_document_id: document.id,
               number: number,
               created_by_id: scope.user.id
             }
             |> LegalDocumentVersion.changeset(attrs)
             |> Repo.insert() do
        after_create(scope, document, version, opts[:publish])
      end
    end)
  end

  defp after_create(scope, document, version, publish?) do
    with {:ok, _} <-
           Audit.record("legal.version_created",
             scope: scope,
             subject: version,
             metadata: %{slug: document.slug, number: version.number}
           ) do
      if publish?, do: publish_version(scope, document, version), else: {:ok, version}
    end
  end

  @doc "Makes `version` the public one (audited)."
  def publish_version(scope, %LegalDocument{} = document, %LegalDocumentVersion{} = version) do
    Repo.transact(fn ->
      document = Repo.one!(from d in LegalDocument, where: d.id == ^document.id, lock: "FOR UPDATE")

      if document.published_version_id == version.id do
        {:ok, Repo.reload!(version)}
      else
        publish_changed_version(scope, document, version)
      end
    end)
  end

  defp publish_changed_version(scope, document, version) do
    with {:ok, published} <-
           version
           |> Ecto.Changeset.change(published_at: DateTime.utc_now(:second))
           |> Repo.update(),
         {:ok, _} <-
           document |> Ecto.Changeset.change(published_version_id: version.id) |> Repo.update(),
         {:ok, _} <-
           Audit.record("legal.published",
             scope: scope,
             subject: published,
             metadata: %{slug: document.slug, number: version.number}
           ) do
      {:ok, published}
    end
  end

  @doc "Gets a version of a document (admin)."
  def get_version!(%LegalDocument{id: doc_id}, number) do
    Repo.get_by!(LegalDocumentVersion, legal_document_id: doc_id, number: number)
  end

  @doc "Records that the scope's user accepted the published version of `slug`."
  def accept(scope, slug, ip_address \\ nil) do
    case Repo.get_by(LegalDocument, slug: slug) do
      %LegalDocument{published_version_id: version_id} when not is_nil(version_id) ->
        %LegalAcceptance{
          user_id: scope.user.id,
          subject_email_hash: email_hash(scope.user.email),
          legal_document_version_id: version_id,
          ip_address: ip_address
        }
        |> Repo.insert(on_conflict: :nothing)

      _ ->
        {:error, :not_found}
    end
  end

  @signup_slugs ~w(terms privacy)

  @doc """
  Records the sign-up consent: one acceptance per published version of the terms and the
  privacy policy (an unpublished document has no text to accept, so it is skipped).
  Call it inside the transaction that creates the user.
  """
  def accept_at_signup(user, ip_address) do
    Enum.reduce_while(@signup_slugs, {:ok, []}, fn slug, {:ok, accepted} ->
      case accept(%{user: user}, slug, ip_address) do
        {:ok, _acceptance} -> {:cont, {:ok, [slug | accepted]}}
        {:error, :not_found} -> {:cont, {:ok, accepted}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  # Same value as the SQL backfill in the KeepLegalAcceptances migration.
  defp email_hash(email),
    do: :sha256 |> :crypto.hash(String.downcase(email)) |> Base.encode16(case: :lower)
end
