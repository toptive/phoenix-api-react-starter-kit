defmodule StarterKitWeb.ApiLegalTest do
  use StarterKitWeb.ConnCase, async: true
  import StarterKitWeb.ApiHelpers
  import Ecto.Query
  alias StarterKit.{Accounts, Audit, Repo}

  setup %{conn: conn} do
    conn = api_conn(conn)
    admin = superadmin_fixture()
    %{conn: conn, auth: bearer(conn, Accounts.generate_api_token(admin).token)}
  end

  test "admin legal index ensures all three documents and show returns the complete document", %{
    auth: auth
  } do
    documents = json_response(get(auth, ~p"/api/v1/admin/legal-documents"), 200)["data"]
    assert Enum.map(documents, & &1["slug"]) == ["cookies", "privacy", "terms"]

    for document <- documents do
      assert document["versions"] == []
      assert document["publishedVersionId"] == nil

      assert json_response(get(auth, ~p"/api/v1/admin/legal-documents/#{document["slug"]}"), 200)[
               "data"
             ] == document
    end

    assert Repo.aggregate(StarterKit.Legal.LegalDocument, :count) == 3
  end

  test "legal resources reject unknown slugs and versions", %{auth: auth} do
    assert_error(get(auth, ~p"/api/v1/admin/legal-documents/unknown"), 404, "not_found")

    assert_error(
      post(auth, ~p"/api/v1/admin/legal-documents/unknown/versions", attrs()),
      404,
      "not_found"
    )

    for slug <- ["terms", "unknown"], number <- ["1", "invalid", "-1"] do
      assert_error(
        post(auth, "/api/v1/admin/legal-documents/#{slug}/versions/#{number}/publication", %{}),
        404,
        "not_found"
      )
    end
  end

  test "new version stays draft, gets the next number and versions are newest first", %{
    auth: auth,
    conn: conn
  } do
    for number <- 1..2 do
      version =
        post(
          auth,
          ~p"/api/v1/admin/legal-documents/terms/versions",
          Map.put(attrs(), :note, "Internal note")
        )
        |> json_response(201)
        |> Map.fetch!("data")

      assert version["number"] == number
      assert version["titles"] == %{"en" => "Terms", "es" => "Términos"}
      assert version["bodies"] == %{"en" => "## Heading\n\nPlain text <script>"}
      assert version["note"] == "Internal note"
      assert version["publishedAt"] == nil
    end

    assert_error(get(conn, ~p"/api/v1/legal-pages/terms"), 404, "not_found")

    doc =
      get(auth, ~p"/api/v1/admin/legal-documents/terms") |> json_response(200) |> Map.fetch!("data")

    assert Enum.map(doc["versions"], & &1["number"]) == [2, 1]
    assert length(events("legal.version_created")) == 2
    assert events("legal.published") == []
  end

  test "version validates required English, note length, map values and publish boolean", %{
    auth: auth
  } do
    for field <- [:titles, :bodies] do
      for value <- [%{}, %{"es" => "Spanish"}, %{"en" => ""}, nil] do
        assert_field(
          post(
            auth,
            ~p"/api/v1/admin/legal-documents/terms/versions",
            Map.put(attrs(), field, value)
          ),
          Atom.to_string(field),
          "validation.english_required"
        )
      end
    end

    assert_field(
      post(auth, ~p"/api/v1/admin/legal-documents/terms/versions", %{
        titles: %{"en" => "Terms", "es" => 2},
        bodies: %{"en" => "Body"}
      }),
      "titles",
      "validation.invalid"
    )

    assert_field(
      post(
        auth,
        ~p"/api/v1/admin/legal-documents/terms/versions",
        Map.put(attrs(), :note, String.duplicate("x", 256))
      ),
      "note",
      "validation.length_max"
    )

    assert_error(
      post(
        auth,
        ~p"/api/v1/admin/legal-documents/terms/versions",
        Map.put(attrs(), :publish, "perhaps")
      ),
      400,
      "bad_request"
    )

    assert_error(
      post(auth, ~p"/api/v1/admin/legal-documents/terms/versions", Map.put(attrs(), :titles, [])),
      400,
      "bad_request"
    )

    assert Repo.aggregate(StarterKit.Legal.LegalDocumentVersion, :count) == 0
    assert events("legal.version_created") == []
  end

  test "publish → public page in request locale → 304 → new publication changes ETag", %{
    conn: conn,
    auth: auth
  } do
    first =
      post(auth, ~p"/api/v1/admin/legal-documents/terms/versions", Map.put(attrs(), :publish, true))
      |> json_response(201)
      |> Map.fetch!("data")

    assert first["publishedAt"] =~ ~r/Z$/
    spanish = get(conn, ~p"/api/v1/legal-pages/terms?locale=es")
    page = json_response(spanish, 200)["data"]
    assert page["title"] == "Términos"
    assert page["body"] == "## Heading\n\nPlain text <script>"
    assert page["slug"] == "terms" and page["version"] == 1
    assert get_resp_header(spanish, "etag") == [~s("terms:1:es")]
    assert get_resp_header(spanish, "cache-control") == ["public, no-cache"]
    assert get_resp_header(spanish, "set-cookie") == []

    assert json_response(
             conn |> put_req_header("accept-language", "es") |> get(~p"/api/v1/legal-pages/terms"),
             200
           )["data"]["title"] == "Términos"

    conditional = put_req_header(conn, "if-none-match", ~s("terms:1:es"))
    assert response(get(conditional, ~p"/api/v1/legal-pages/terms?locale=es"), 304) == ""

    post(auth, ~p"/api/v1/admin/legal-documents/terms/versions", %{
      titles: %{en: "Updated"},
      bodies: %{en: "New body"}
    })
    |> json_response(201)

    document =
      post(auth, ~p"/api/v1/admin/legal-documents/terms/versions/2/publication", %{})
      |> json_response(201)
      |> Map.fetch!("data")

    assert document["publishedVersionId"] == hd(document["versions"])["id"]
    changed = get(conditional, ~p"/api/v1/legal-pages/terms?locale=es")
    assert json_response(changed, 200)["data"]["title"] == "Updated"
    assert get_resp_header(changed, "etag") == [~s("terms:2:es")]
    assert length(events("legal.published")) == 2

    assert json_response(
             post(auth, ~p"/api/v1/admin/legal-documents/terms/versions/2/publication", %{}),
             201
           )["data"] == document

    assert length(events("legal.published")) == 2
  end

  test "public legal page returns 404 for unknown or unpublished slug", %{conn: conn} do
    for slug <- ["unknown", "terms", "privacy", "cookies"] do
      result = get(conn, ~p"/api/v1/legal-pages/#{slug}")
      assert_error(result, 404, "not_found")
      assert get_resp_header(result, "cache-control") == ["private, no-store"]
    end
  end

  defp attrs,
    do: %{
      titles: %{en: "Terms", es: "Términos"},
      bodies: %{en: "## Heading\n\nPlain text <script>"}
    }

  defp events(action), do: Repo.all(from e in Audit.AuditEvent, where: e.action == ^action)
end
