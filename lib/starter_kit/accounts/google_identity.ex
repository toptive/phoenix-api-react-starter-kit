defmodule StarterKit.Accounts.GoogleIdentity do
  @moduledoc false

  @doc false
  def exchange(code, redirect_uri, locale) do
    config = Application.get_env(:ueberauth, Ueberauth.Strategy.Google.OAuth, [])
    options = Application.get_env(:starter_kit, :google_req_options, [])

    with {:ok, %{status: 200, body: %{"access_token" => token}}} <-
           Req.post(
             "https://oauth2.googleapis.com/token",
             Keyword.merge(options,
               form: [
                 code: code,
                 client_id: config[:client_id],
                 client_secret: config[:client_secret],
                 redirect_uri: redirect_uri,
                 grant_type: "authorization_code"
               ],
               retry: false
             )
           ),
         {:ok, %{status: 200, body: %{"sub" => uid, "email" => email} = info}} <-
           Req.get(
             "https://openidconnect.googleapis.com/v1/userinfo",
             Keyword.merge(options, headers: [{"authorization", "Bearer " <> token}], retry: false)
           ),
         true <- info["email_verified"] == true || {:error, :email_not_verified} do
      {:ok, %{uid: uid, email: email, email_verified: true, name: info["name"], locale: locale}}
    else
      {:error, :email_not_verified} -> {:error, :email_not_verified}
      _ -> {:error, :oauth_failed}
    end
  end
end
