defmodule StarterKitWeb.ConnCase do
  @moduledoc "Controller tests: a conn, the sandbox, sign-in helpers and API assertions."

  use Boundary, top_level?: true, check: [in: false, out: false]

  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint StarterKitWeb.Endpoint

      use StarterKitWeb, :verified_routes

      import Plug.Conn
      import Phoenix.ConnTest
      import StarterKit.Fixtures
      import StarterKit.FlagHelpers
      import StarterKitWeb.ConnCase
    end
  end

  setup tags do
    StarterKit.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc "Setup helper: a signed-in user with a personal organization."
  def register_and_log_in_user(%{conn: conn}) do
    user = StarterKit.Fixtures.user_fixture()
    scope = StarterKit.Fixtures.scope_fixture(user)
    %{conn: log_in_user(conn, user), user: user, scope: scope}
  end

  @doc "Setup helper: a signed-in superadmin."
  def register_and_log_in_superadmin(%{conn: conn}) do
    user = StarterKit.Fixtures.superadmin_fixture()
    scope = StarterKit.Fixtures.scope_fixture(user)
    %{conn: log_in_user(conn, user), user: user, scope: scope}
  end

  @doc "Puts a fresh session token for `user` in the conn."
  def log_in_user(conn, user) do
    token = StarterKit.Accounts.generate_user_session_token(user)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end
end
