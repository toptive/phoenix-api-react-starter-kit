defmodule StarterKitWeb.Responses do
  @moduledoc """
  Response helpers imported in every controller: translated flash and Inertia errors,
  the scope shortcut, and the `/api/v1` envelopes.
  """

  import Plug.Conn
  import Phoenix.Controller

  alias StarterKit.I18n
  alias StarterKitWeb.Plugs.PublicPage

  @doc "SPA sign-in destination for unconverted browser areas."
  def spa_sign_in_url, do: StarterKitWeb.ApiAuth.spa_url("/session/new")

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

  @doc "Success envelope. Pass a serialized map or `{serializer, value}`."
  def render_data(conn, data, meta \\ %{}) do
    data =
      case data do
        {serializer, value} -> serializer.serialize(value)
        value -> value
      end

    json(conn, %{data: data, meta: camelize(meta)})
  end

  @doc "Serializes a collection with pagination metadata."
  def render_collection(conn, list, serializer, page_meta) do
    render_data(conn, serializer.serialize_many(list), page_meta)
  end

  @doc "Stable error code, translated message and camelCase details."
  def render_error(conn, status, code, details \\ %{}) do
    conn |> put_status(status) |> json(error_body(conn, code, details))
  end

  @doc "Shared error envelope for last-resort Phoenix error rendering."
  def error_body(conn, code, details \\ %{}) do
    %{
      error: %{
        code: to_string(code),
        message: error_message(conn, code),
        details: camelize(details)
      }
    }
  end

  @doc "Renders translated field validation; wrong JSON types are malformed requests."
  def render_validation_error(conn, changeset) do
    wrong_type =
      Enum.any?(changeset.errors, fn {field, {_message, opts}} ->
        opts[:validation] == :cast and
          not match?({:parameterized, {Ecto.Enum, _}}, changeset.types[field])
      end)

    if wrong_type,
      do: render_error(conn, 400, :bad_request),
      else:
        render_error(
          conn,
          422,
          :validation_failed,
          I18n.validation_details(changeset, locale(conn))
        )
  end

  defp error_message(conn, code) do
    key = "errors.api.#{code}"

    if Map.has_key?(I18n.catalog(locale(conn)), key),
      do: t(conn, key),
      else: t(conn, "errors.api.internal_error")
  end

  defp camelize(%{__struct__: _} = value), do: value

  defp camelize(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {camel_key(key), camelize(value)} end)

  defp camelize(list) when is_list(list), do: Enum.map(list, &camelize/1)
  defp camelize(value), do: value

  defp camel_key(key) do
    key = to_string(key)

    if Regex.match?(~r/^[a-z][a-z0-9]*(?:_[a-z0-9]+)+$/, key) do
      [first | rest] = String.split(key, "_")
      first <> Enum.map_join(rest, &String.capitalize/1)
    else
      key
    end
  end
end
