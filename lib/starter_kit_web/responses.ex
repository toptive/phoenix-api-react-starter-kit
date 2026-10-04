defmodule StarterKitWeb.Responses do
  @moduledoc """
  Response helpers imported in every controller: translated flash and Inertia errors,
  the scope shortcut, and the `/api/v1` envelopes.
  """

  import Plug.Conn
  import Phoenix.Controller

  alias StarterKit.I18n
  alias StarterKitWeb.Plugs.PublicPage

  @doc "The current scope."
  def scope(conn), do: conn.assigns[:current_scope]

  @doc "The request locale (set by `StarterKitWeb.Plugs.Locale`)."
  def locale(conn), do: conn.assigns[:locale] || I18n.default_locale()

  @doc "Translates `key` in the request locale."
  def t(conn, key, bindings \\ %{}), do: I18n.t(key, bindings, locale(conn))

  @doc "Puts a translated flash message."
  def put_flash_t(conn, kind, key, bindings \\ %{}),
    do: put_flash(conn, kind, t(conn, key, bindings))

  @doc "Assigns translated changeset errors for the Inertia form (`errors` prop)."
  def assign_changeset_errors(conn, %Ecto.Changeset{} = changeset) do
    assign_form_errors(conn, I18n.translate_changeset_errors(changeset, locale(conn)))
  end

  @doc "Assigns one translated error on `field`."
  def assign_error(conn, field, key, bindings \\ %{}) do
    assign_form_errors(conn, %{to_string(field) => t(conn, key, bindings)})
  end

  # Inertia camelizes the keys (password_confirmation → passwordConfirmation), which
  # matches the camelCase field names of the React forms.
  defp assign_form_errors(conn, errors), do: Inertia.Controller.assign_errors(conn, errors)

  @doc """
  Renders a public, indexable page. Server-side rendered when SSR is on
  (`config :starter_kit, :ssr`), so crawlers get full HTML. An anonymous full-page load
  is cacheable and can answer `304` before SSR (`StarterKitWeb.Plugs.PublicPage.cache/3`).
  """
  def render_public(conn, component, props) do
    conn = assign(conn, :indexable, true)

    case PublicPage.cache(conn, component, props) do
      {:not_modified, conn} ->
        send_resp(conn, 304, "")

      {:render, conn} ->
        Inertia.Controller.render_inertia(conn, component, props,
          ssr: Application.get_env(:starter_kit, :ssr, false)
        )
    end
  end

  @doc "`/api/v1` success envelope: `{ data, meta? }`."
  def render_data(conn, data, opts \\ []) do
    body = %{data: data} |> then(&if(opts[:meta], do: Map.put(&1, :meta, opts[:meta]), else: &1))

    conn
    |> put_status(opts[:status] || 200)
    |> json(body)
  end

  @doc "`/api/v1` error envelope: `{ error: { code, message, details } }`."
  def render_error(conn, status, code, details \\ %{}) do
    conn
    |> put_status(status)
    |> json(%{
      error: %{
        code: to_string(code),
        message: t(conn, "errors.api.#{code}"),
        details: details
      }
    })
  end
end
