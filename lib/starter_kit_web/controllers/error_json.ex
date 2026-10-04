defmodule StarterKitWeb.ErrorJSON do
  @moduledoc "Last-resort JSON errors in the `/api/v1` error envelope."

  alias StarterKitWeb.Responses

  def render(template, assigns) do
    status = template |> String.split(".") |> hd()

    code =
      Map.get(
        %{
          "400" => "bad_request",
          "403" => "forbidden",
          "404" => "not_found",
          "401" => "unauthorized",
          "422" => "validation_failed",
          "429" => "rate_limited"
        },
        status,
        "internal_error"
      )

    conn = assigns[:conn] || %Plug.Conn{}
    Responses.error_body(conn, code)
  end
end
