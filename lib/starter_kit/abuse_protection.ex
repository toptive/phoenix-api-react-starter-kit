defmodule StarterKit.AbuseProtection do
  @moduledoc """
  Cloudflare Turnstile on anonymous forms that create work (sign-up, "email me a link").

  The flag `:turnstile` (`TURNSTILE_REQUIRED`, default off) turns it on. When it is on:

    * the page gets the public site key (`widget/0`, the `turnstile` shared prop) and
      renders `components/app/turnstile.tsx`;
    * `StarterKitWeb.Plugs.VerifyTurnstile` calls `verify/3` before the controller action.

  `verify/3` fails closed: a missing, malformed or used token, another hostname or action,
  a provider error, a timeout or a missing secret all refuse the request. One try, 5 s.

  Cloudflare's test keys (`1x000…`, `2x000…`, `3x000…`) work in dev: their answer has no
  hostname or action, so it counts only while the configured secret is a test secret.
  Production refuses test keys at boot (`config_problems/0`, `StarterKit.Flags.check!/1`).
  """

  use Boundary, top_level?: true, deps: [StarterKit.Flags], exports: []

  alias StarterKit.Flags

  @actions ~w(registration magic_link)
  @siteverify "https://challenges.cloudflare.com/turnstile/v0/siteverify"
  @test_key_prefixes ["1x000", "2x000", "3x000"]

  @doc "The actions a form may send (the widget `action` and the plug option)."
  def actions, do: @actions

  @doc "True when anonymous forms must pass a Turnstile challenge."
  def required?, do: Flags.enabled?(:turnstile)

  @doc "What the page needs to render the widget. Never the secret; no key when off."
  def widget do
    if required?(),
      do: %{required: true, site_key: config()[:site_key]},
      else: %{required: false, site_key: nil}
  end

  @doc "`:ok` when protection is off or Cloudflare accepts `token` for `action`."
  def verify(token, action, remote_ip) when action in @actions do
    if required?(), do: verify_remote(token, action, remote_ip), else: :ok
  end

  defp verify_remote(token, action, remote_ip)
       when is_binary(token) and byte_size(token) in 1..2048 do
    config = config()
    secret = config[:secret_key]
    hostname = config[:hostname]

    with true <- present?(secret) and present?(hostname),
         {:ok, %{status: 200, body: %{} = body}} <-
           Req.post(@siteverify, request_options(config, secret, token, remote_ip)),
         true <- accepted?(body, hostname, action, secret) do
      :ok
    else
      _ -> {:error, :verification_required}
    end
  end

  defp verify_remote(_token, _action, _remote_ip), do: {:error, :verification_required}

  defp request_options(config, secret, token, remote_ip) do
    Keyword.merge(
      [
        form: [secret: secret, response: token, remoteip: remote_ip |> :inet.ntoa() |> to_string()],
        receive_timeout: 5_000,
        connect_options: [timeout: 3_000],
        retry: false,
        redirect: false
      ],
      config[:req_options] || []
    )
  end

  defp accepted?(
         %{"success" => true, "hostname" => hostname, "action" => action},
         hostname,
         action,
         _
       ),
       do: true

  defp accepted?(
         %{"success" => true, "metadata" => %{"result_with_testing_key" => true}},
         _,
         _,
         secret
       ),
       do: test_key?(secret)

  defp accepted?(_body, _hostname, _action, _secret), do: false

  @doc """
  What stops Turnstile from working: a missing key or hostname, or a Cloudflare test key.
  With the flag ON, a problem stops the boot in production (`StarterKit.Flags.check!/1`).
  """
  def config_problems(config \\ config()) do
    [
      {not present?(config[:site_key]), "TURNSTILE_SITE_KEY is missing"},
      {not present?(config[:secret_key]), "TURNSTILE_SECRET_KEY is missing"},
      {not present?(config[:hostname]), "TURNSTILE_HOSTNAME (or PHX_HOST) is missing"},
      {test_key?(config[:site_key]) or test_key?(config[:secret_key]),
       "a Cloudflare test key cannot protect production"}
    ]
    |> Enum.flat_map(fn {problem?, message} -> if problem?, do: [message], else: [] end)
  end

  defp test_key?(key), do: is_binary(key) and String.starts_with?(key, @test_key_prefixes)
  defp present?(value), do: is_binary(value) and value != ""
  defp config, do: Application.get_env(:starter_kit, __MODULE__, [])
end
