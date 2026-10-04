defmodule StarterKit.LegalTest do
  use StarterKit.DataCase, async: true

  alias StarterKit.Accounts.Scope
  alias StarterKit.Legal

  setup do
    %{scope: Scope.for_user(superadmin_fixture())}
  end

  test "versions are numbered, published explicitly, and shown per locale", %{scope: scope} do
    [terms | _] = Legal.list_documents(scope) |> Enum.filter(&(&1.slug == "terms"))
    assert {:error, :not_found} = Legal.published_page("terms", "en")

    {:ok, v1} =
      Legal.create_version(scope, terms, %{
        "titles" => %{"en" => "Terms", "es" => "Términos"},
        "bodies" => %{"en" => "Body"}
      })

    assert v1.number == 1
    assert {:error, :not_found} = Legal.published_page("terms", "en")

    {:ok, _} = Legal.publish_version(scope, terms, v1)

    assert {:ok, %{title: "Términos", body: "Body", version: 1}} =
             Legal.published_page("terms", "es")

    assert "terms" in Legal.published_slugs()
  end

  test "English is required", %{scope: scope} do
    [doc | _] = Legal.list_documents(scope)

    assert {:error, changeset} =
             Legal.create_version(scope, doc, %{
               "titles" => %{"es" => "x"},
               "bodies" => %{"es" => "y"}
             })

    assert "validation.english_required" in errors_on(changeset).titles
  end

  test "acceptance records the exact version", %{scope: scope} do
    [doc | _] = Legal.list_documents(scope) |> Enum.filter(&(&1.slug == "privacy"))

    {:ok, _} =
      Legal.create_version(scope, doc, %{"titles" => %{"en" => "P"}, "bodies" => %{"en" => "B"}},
        publish: true
      )

    assert {:ok, acceptance} = Legal.accept(scope, "privacy", "127.0.0.1")
    assert acceptance.legal_document_version_id
  end

  test "an acceptance outlives the account that gave it", %{scope: admin} do
    [doc | _] = Legal.list_documents(admin) |> Enum.filter(&(&1.slug == "terms"))

    {:ok, _} =
      Legal.create_version(admin, doc, %{"titles" => %{"en" => "T"}, "bodies" => %{"en" => "B"}},
        publish: true
      )

    user = user_fixture()
    {:ok, acceptance} = Legal.accept(Scope.for_user(user), "terms", "127.0.0.1")
    {:ok, _} = StarterKit.Accounts.delete_user(Scope.for_user(user))

    kept = Repo.get!(StarterKit.Legal.LegalAcceptance, acceptance.id)
    assert kept.user_id == nil

    assert kept.subject_email_hash ==
             :sha256 |> :crypto.hash(String.downcase(user.email)) |> Base.encode16(case: :lower)
  end
end
