defmodule StarterKit.Fixtures do
  @moduledoc "Test data builders. Each returns a persisted record."

  use Boundary, top_level?: true, check: [in: false, out: false]

  alias StarterKit.Accounts.{Scope, User}
  alias StarterKit.{Organizations, Repo}

  def unique_email, do: "user#{System.unique_integer([:positive])}@example.com"

  @doc "A confirmed user (no password unless `password:` is given)."
  def user_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)

    user =
      %User{
        email: attrs[:email] || unique_email(),
        name: Map.get(attrs, :name, "Test User"),
        role: attrs[:role] || :user,
        locale: attrs[:locale] || "en",
        confirmed_at: Map.get(attrs, :confirmed_at, DateTime.utc_now(:second)),
        hashed_password: attrs[:password] && Bcrypt.hash_pwd_salt(attrs[:password])
      }
      |> Repo.insert!()

    %{user | authenticated_at: DateTime.utc_now(:second)}
  end

  def superadmin_fixture(attrs \\ %{}),
    do: user_fixture(Map.put(Map.new(attrs), :role, :superadmin))

  @doc """
  The scope of `user` in their first organization (created on demand). The organization
  counts as onboarded (an existing user); `onboarded: false` keeps it new.
  """
  def scope_fixture(user \\ user_fixture(), opts \\ []) do
    scope = user |> Scope.for_user() |> Organizations.scope_for()

    if Keyword.get(opts, :onboarded, true) and is_nil(scope.organization.onboarded_at) do
      org =
        scope.organization
        |> Ecto.Changeset.change(onboarded_at: DateTime.utc_now(:second))
        |> Repo.update!()

      Scope.put_organization(scope, org, scope.membership)
    else
      scope
    end
  end

  @doc """
  A Stripe subscription for the organization of `scope`, as reconciliation would store
  it: paid `"pro"` in test mode until 30 days from now unless `attrs` say otherwise.
  """
  def subscription_fixture(scope, attrs \\ %{}) do
    Repo.insert!(
      struct(
        %StarterKit.Billing.Subscription{
          organization_id: scope.organization.id,
          livemode: false,
          stripe_customer_id: "cus_#{System.unique_integer([:positive])}",
          stripe_subscription_id: "sub_#{System.unique_integer([:positive])}",
          offer_id: "pro_monthly",
          plan: "pro",
          status: "active",
          current_period_end: DateTime.add(DateTime.utc_now(:second), 30, :day)
        },
        attrs
      )
    )
  end

  @doc "Adds `user` to the organization of `scope` with `role`/`access`."
  def membership_fixture(scope, user, role \\ :member, access \\ :full) do
    Repo.insert!(%Organizations.Membership{
      organization_id: scope.organization.id,
      user_id: user.id,
      role: role,
      access: access
    })
  end

  @doc "Extracts the token from a `url_fun` callback."
  def capture_token(fun) do
    {:ok, captured} = Agent.start_link(fn -> nil end)
    fun.(fn token -> Agent.update(captured, fn _ -> token end) && "http://test/#{token}" end)
    Agent.get(captured, & &1)
  end
end
