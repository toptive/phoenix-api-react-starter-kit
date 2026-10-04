defmodule StarterKitWeb.ApiHelpers do
  @moduledoc "HTTP API and emailed-link helpers for request and flow tests."
  use Boundary, top_level?: true, check: [in: false, out: false]
  import ExUnit.Assertions
  import Phoenix.ConnTest
  import Plug.Conn
  @endpoint StarterKitWeb.Endpoint

  def api_conn(conn) do
    ip = System.unique_integer([:positive])

    %{
      (conn
       |> put_req_header("accept", "application/json")
       |> put_req_header("content-type", "application/json"))
      | remote_ip: {10, rem(div(ip, 65_536), 250), rem(div(ip, 256), 250), rem(ip, 250)}
    }
  end

  def bearer(conn, token), do: put_req_header(conn, "authorization", "Bearer " <> token)

  def sign_in(conn, user, password \\ "correct horse battery") do
    conn
    |> post("/api/v1/auth/sessions", %{email: user.email, password: password})
    |> json_response(201)
    |> Map.fetch!("data")
  end

  def email_token(path) do
    assert_receive {:email, email}
    [_, token] = Regex.run(~r{#{Regex.escape(path)}([a-zA-Z0-9_-]+)}, email.text_body)
    token
  end

  def request_magic(conn, email) do
    assert json_response(post(conn, "/api/v1/auth/magic-links", %{email: email}), 202)
    email_token("/magic-links/")
  end

  def current_auth(conn),
    do: conn |> get("/api/v1/bootstrap") |> json_response(200) |> get_in(["data", "auth"])

  def assert_error(conn, status, code) do
    assert %{"error" => %{"code" => ^code, "message" => message, "details" => details}} =
             json_response(conn, status)

    assert is_binary(message) and is_map(details)
    details
  end

  def assert_field(conn, field, key) do
    details = assert_error(conn, 422, "validation_failed")
    assert Enum.any?(details[field], &(&1["key"] == key and is_binary(&1["message"])))
    details[field]
  end
end
