defmodule StarterKit.I18nTest do
  use StarterKit.DataCase, async: false

  alias StarterKit.Accounts.Scope
  alias StarterKit.I18n
  alias StarterKit.I18n.{Reference, Translation}

  setup do
    I18n.sync()
    on_exit(&StarterKit.I18n.Catalog.reset_to_reference/0)
    :ok
  end

  test "t/3 interpolates, falls back to English, and returns the key when unknown" do
    assert I18n.t("dashboard.greeting", %{name: "Ana"}, "es") == "Hola, Ana"
    assert I18n.t("no.such.key", %{}, "es") == "no.such.key"
  end

  test "t/3 picks the plural form from count" do
    assert I18n.t("flash.admin.translations_filled", %{count: 1}, "en") =~ "1 text filled"
    assert I18n.t("flash.admin.translations_filled", %{count: 3}, "en") =~ "3 texts filled"
  end

  test "changeset errors are translated by key or by validation" do
    changeset =
      {%{}, %{name: :string, email: :string}}
      |> Ecto.Changeset.cast(%{email: "bad"}, [:name, :email])
      |> Ecto.Changeset.validate_required([:name])
      |> Ecto.Changeset.validate_format(:email, ~r/@/, message: "validation.email_format")

    assert %{"name" => "Este campo es obligatorio.", "email" => email} =
             I18n.translate_changeset_errors(changeset, "es")

    assert email =~ "ejemplo.com"
  end

  test "admin edits win over the CSV and survive a sync" do
    admin = superadmin_fixture()
    scope = Scope.for_user(admin)
    {:ok, _} = I18n.update_translation(scope, "nav.home", "es", "Portada")
    assert I18n.t("nav.home", %{}, "es") == "Portada"

    I18n.sync()
    assert Repo.get_by!(Translation, key: "nav.home", locale: "es").value == "Portada"
  end

  test "sync refreshes rows nobody edited and removes keys that left the CSV" do
    Repo.update_all(from(t in Translation, where: t.key == "nav.home" and t.locale == "en"),
      set: [value: "Old"]
    )

    Repo.insert!(%Translation{key: "gone.key", locale: "en", value: "x"})

    assert %{updated: 1, deleted: 1} = I18n.sync()

    assert Repo.get_by!(Translation, key: "nav.home", locale: "en").value ==
             Reference.catalog("en")["nav.home"]
  end

  test "fill_missing translates empty cells through the AI module" do
    Repo.update_all(from(t in Translation, where: t.key == "nav.home" and t.locale == "es"),
      set: [value: ""]
    )

    Process.put(:ai_response, fn body ->
      [_, %{content: json}] = body.messages
      filled = json |> Jason.decode!() |> Map.new(fn {k, _} -> {k, "ES #{k}"} end)
      {:ok, %{"choices" => [%{"message" => %{"content" => Jason.encode!(filled)}}]}}
    end)

    # Only keys whose CSV cell is empty are "missing"; the test CSV has none, so nothing is sent.
    assert {:ok, 0} = I18n.fill_missing(Scope.for_user(superadmin_fixture()), "es")

    assert {:error, :unsupported_locale} =
             I18n.fill_missing(Scope.for_user(superadmin_fixture()), "en")
  end

  test "every locale in the CSV has every key filled" do
    for {key, values} <- Reference.rows(), locale <- Reference.locales() do
      assert values[locale] != "", "#{key} has no #{locale} text"
    end
  end
end
