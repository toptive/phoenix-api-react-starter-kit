defmodule StarterKitWeb.SignupTest do
  # Not async: SIGNUP_MODE is global application config.
  use StarterKitWeb.ConnCase, async: false

  alias StarterKit.Accounts

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
      assert redirected_to(scanner) =~ "http://localhost:5173/auth/session"
      assert Accounts.get_email_change(user, token)
    end
  end
end
