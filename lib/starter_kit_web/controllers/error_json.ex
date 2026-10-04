defmodule StarterKitWeb.ErrorJSON do
  @moduledoc "Last-resort JSON errors in the `/api/v1` error envelope."

  alias StarterKit.I18n

  def render(template, assigns) do
    status = template |> String.split(".") |> hd()

    code =
      Map.get(
        %{
          "400" => "bad_request",
          "403" => "forbidden",
          "404" => "not_found",
          "422" => "validation_error",
          "429" => "too_many_requests"
        },
        status,
        "internal_error"
      )

    locale = assigns[:conn] && assigns.conn.assigns[:locale]

    %{error: %{code: code, message: I18n.t("errors.api.#{code}", %{}, locale), details: %{}}}
  end
end
