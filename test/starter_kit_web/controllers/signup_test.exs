defmodule StarterKitWeb.SignupTest do
  # Not async: SIGNUP_MODE is global application config.
  use StarterKitWeb.ConnCase, async: false

  import Swoosh.TestAssertions

  alias StarterKit.Accounts

  setup do
    on_exit(fn -> Application.put_env(:starter_kit, :signup_mode, :open) end)
  end

  defp signup_mode(mode), do: Application.put_env(:starter_kit, :signup_mode, mode)

  defp user_params(extra \\ %{}),
    do: Map.merge(%{"name" => "Ana", "email" => unique_email(), "termsAccepted" => true}, extra)

  describe "registration" do
    test "the page says the sign-up mode", %{conn: conn} do
      for mode <- [:open, :invite, :closed] do
        signup_mode(mode)
        assert conn |> get(~p"/registration/new") |> inertia_props() |> Map.get(:signupMode) == mode
        assert conn |> get(~p"/session/new") |> inertia_props() |> Map.get(:signupMode) == mode
      end
    end

    test "the terms checkbox is required", %{conn: conn} do
      params = user_params(%{"termsAccepted" => false})
      conn = post(conn, ~p"/registration", %{"user" => params})

      assert redirected_to(conn) == ~p"/registration/new"
      assert get_session(conn, "inertia_errors")["terms_accepted"] =~ "terms"
      refute Accounts.get_user_by_email(params["email"])
    end

    test "invite mode refuses an email without an invitation", %{conn: conn} do
      signup_mode(:invite)
      params = user_params()
      conn = post(conn, ~p"/registration", %{"user" => params})

      assert redirected_to(conn) == ~p"/registration/new"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "invitation"
      refute Accounts.get_user_by_email(params["email"])
      assert_no_email_sent()
    end

    test "closed mode refuses", %{conn: conn} do
      signup_mode(:closed)
      conn = post(conn, ~p"/registration", %{"user" => user_params()})

      assert redirected_to(conn) == ~p"/registration/new"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "new accounts"
    end
  end

  describe "email change link" do
    setup :register_and_log_in_user

    test "the GET shows a button; only the POST changes the email", %{conn: conn, user: user} do
      new_email = unique_email()
      scope = Accounts.Scope.for_user(user)

      token =
        capture_token(&Accounts.request_email_change(scope, %{"email" => new_email}, &1))

      page = get(conn, ~p"/settings/email-confirmations/#{token}")
      assert inertia_component(page) == "settings/email-confirmations/show"
      assert inertia_props(page).email == new_email
      assert Accounts.get_user!(user.id).email == user.email

      conn = post(conn, ~p"/settings/email-confirmations", %{"token" => token})
      assert redirected_to(conn) == ~p"/settings/email/edit"
      assert Accounts.get_user!(user.id).email == new_email

      # The link is single-use.
      again = conn |> recycle() |> get(~p"/settings/email-confirmations/#{token}")
      assert redirected_to(again) == ~p"/settings/email/edit"
    end

    test "a link scanner without the session cannot use it", %{user: user} do
      scope = Accounts.Scope.for_user(user)

      token =
        capture_token(&Accounts.request_email_change(scope, %{"email" => unique_email()}, &1))

      scanner = get(build_conn(), ~p"/settings/email-confirmations/#{token}")
      assert redirected_to(scanner) =~ "/session/new"
      assert Accounts.get_email_change(user, token)
    end
  end
end
