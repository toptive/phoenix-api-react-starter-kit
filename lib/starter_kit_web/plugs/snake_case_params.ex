defmodule StarterKitWeb.Plugs.SnakeCaseParams do
  @moduledoc """
  The wire is camelCase in both directions: props and JSON go out camelized (  `camelize_props` + serializers), and form/JSON keys come in camelCase
  (`passwordConfirmation`). This plug turns incoming keys into snake_case before the
  controller sees them. Only identifier-like keys change (`rememberMe`); data keys such
  as locales (`zh-HK`) or translation keys (`nav.home`) are left alone.
  """

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{params: params} = conn, _opts) do
    %{conn | params: convert(params), body_params: convert(conn.body_params)}
  end

  defp convert(%Plug.Conn.Unfetched{} = unfetched), do: unfetched
  defp convert(%{__struct__: _} = struct), do: struct
  defp convert(map) when is_map(map), do: Map.new(map, fn {k, v} -> {key(k), convert(v)} end)
  defp convert(list) when is_list(list), do: Enum.map(list, &convert/1)
  defp convert(value), do: value

  defp key(k) when is_binary(k) do
    if Regex.match?(~r/^[a-z][a-z0-9]*[A-Z][A-Za-z0-9]*$/, k), do: Macro.underscore(k), else: k
  end

  defp key(k), do: k
end
