defmodule StarterKitWeb.Layouts do
  @moduledoc "The root HTML document. Everything inside `#app` is React (Inertia)."

  use StarterKitWeb, :html

  embed_templates "layouts/*"

  @doc """
  The `<title>` text. An SSR page's title comes from React's `<Head title>`: Inertia moves
  it into the `page_title` assign as React wrote it, already HTML-escaped. It is unescaped
  here because HEEx escapes it again (else "Terms & privacy" shows as "Terms &amp;
  privacy"). Without SSR (or without a title): the app name; the client sets the title.
  """
  def page_title(assigns) do
    case assigns[:page_title] do
      title when is_binary(title) and title != "" -> unescape_html(title)
      _ -> Application.get_env(:starter_kit, :app_name, "StarterKit")
    end
  end

  # The five entities React's renderToString writes in text; `&amp;` last, so "&amp;lt;"
  # becomes the text "&lt;", not "<".
  defp unescape_html(text) do
    text
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#x27;", "'")
    |> String.replace("&#39;", "'")
    |> String.replace("&amp;", "&")
  end
end
