# Development data. `mix ecto.setup` runs it; it is safe to run twice.
# Never run seeds against production (docs/DEPLOY.md).

alias StarterKit.Accounts.User
alias StarterKit.{I18n, Legal, Repo}

IO.inspect(I18n.sync(), label: "i18n sync")

admin =
  Repo.get_by(User, email: "admin@example.com") ||
    Repo.insert!(%User{
      email: "admin@example.com",
      name: "Ada Admin",
      role: :superadmin,
      locale: "en",
      confirmed_at: DateTime.utc_now(:second),
      hashed_password: Bcrypt.hash_pwd_salt("password1234")
    })

Repo.get_by(User, email: "member@example.com") ||
  Repo.insert!(%User{
    email: "member@example.com",
    name: "Mateo Miembro",
    locale: "es",
    confirmed_at: DateTime.utc_now(:second),
    hashed_password: Bcrypt.hash_pwd_salt("password1234")
  })

# Each seeded user gets their organization now (otherwise on first sign-in).
for email <- ["admin@example.com", "member@example.com"] do
  User
  |> Repo.get_by!(email: email)
  |> StarterKit.Accounts.Scope.for_user()
  |> StarterKit.Organizations.scope_for()
end

scope = StarterKit.Accounts.Scope.for_user(admin)

placeholder = fn title ->
  """
  ## #{title}

  This is placeholder text. Replace it in Admin → Legal documents before launch.

  ## Contact

  Write to hello@example.com.
  """
end

for document <- Legal.list_documents(scope), document.versions == [] do
  title =
    %{"terms" => "Terms of service", "privacy" => "Privacy policy", "cookies" => "Cookie policy"}[
      document.slug
    ]

  {:ok, _} =
    Legal.create_version(
      scope,
      document,
      %{"titles" => %{"en" => title}, "bodies" => %{"en" => placeholder.(title)}, "note" => "Seed"},
      publish: true
    )
end

IO.puts("Seeded: admin@example.com / password1234 (superadmin), member@example.com / password1234")
