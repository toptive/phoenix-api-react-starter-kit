defmodule StarterKit.AI do
  @moduledoc """
  The ONE module that calls AI providers. Toptive rule: OpenRouter for LLMs, fal.ai for
  image/audio/video, Google for Gemini/TTS — never OpenAI or Anthropic directly.

      AI.chat([%{role: "user", content: "Hi"}])                  # OpenRouter
      AI.translate_strings(%{"a.b" => "Save"}, from: "en", to: "es")
      AI.fal("fal-ai/flux/schnell", %{prompt: "a quiet harbour"}) # fal.ai
      AI.gemini("Summarise …")                                    # Google

  Keys and models come from the environment (`OPENROUTER_API_KEY`, `OPENROUTER_MODEL`,
  `FAL_KEY`, `GOOGLE_API_KEY`, `GEMINI_MODEL`). A missing key returns
  `{:error, :not_configured}`; there is no silent fallback to another provider.
  """

  use Boundary, top_level?: true, deps: [], exports: []

  @openrouter_url "https://openrouter.ai/api/v1/chat/completions"
  @fal_url "https://fal.run/"
  @gemini_url "https://generativelanguage.googleapis.com/v1beta/models/"

  @doc "Whether OpenRouter is configured for synchronous translation fills."
  def configured?, do: match?({:ok, _}, key(:openrouter_api_key))

  @doc "Chat completion through OpenRouter. Returns `{:ok, text}`."
  def chat(messages, opts \\ []) do
    with {:ok, key} <- key(:openrouter_api_key) do
      body =
        %{
          model: opts[:model] || config(:openrouter_model) || "openai/gpt-4o-mini",
          messages: messages,
          temperature: opts[:temperature] || 0.2
        }
        |> maybe_put(:response_format, opts[:response_format])
        |> maybe_put(:max_tokens, opts[:max_tokens])

      headers = [
        {"authorization", "Bearer #{key}"},
        {"x-title", config(:app_name) || "StarterKit"}
      ]

      case http().post(@openrouter_url, headers, body, opts) do
        {:ok, %{"choices" => [%{"message" => %{"content" => text}} | _]}} -> {:ok, text}
        {:ok, other} -> {:error, {:unexpected, other}}
        error -> error
      end
    end
  end

  @doc """
  Translates a map of `key => text` from one locale to another (UI copy). Keeps
  `{{placeholders}}` untouched. Returns `{:ok, %{key => text}}`.
  """
  def translate_strings(strings, from: from, to: to) when is_map(strings) do
    system = """
    You translate short user-interface strings for a web app used by non-technical people.
    Translate from #{from} to #{to}. Keep the same JSON keys. Keep {{placeholders}} exactly.
    Use plain, friendly words. Answer with a JSON object only.
    """

    with {:ok, text} <-
           chat(
             [%{role: "system", content: system}, %{role: "user", content: Jason.encode!(strings)}],
             response_format: %{type: "json_object"}
           ),
         {:ok, %{} = translated} <- Jason.decode(text) do
      {:ok, Map.new(translated, fn {k, v} -> {k, to_string(v)} end)}
    else
      {:ok, _} -> {:error, :invalid_response}
      error -> error
    end
  end

  @doc "Runs a fal.ai model synchronously (`fal.run`). Returns the model's JSON."
  def fal(model, input, opts \\ []) do
    with {:ok, key} <- key(:fal_key) do
      http().post(
        @fal_url <> model,
        [{"authorization", "Key #{key}"}],
        input,
        Keyword.put_new(opts, :timeout, 300_000)
      )
    end
  end

  @doc "Google Gemini text generation. Returns `{:ok, text}`."
  def gemini(prompt, opts \\ []) do
    with {:ok, key} <- key(:google_api_key) do
      model = opts[:model] || config(:gemini_model) || "gemini-2.5-flash"
      body = %{contents: [%{parts: [%{text: prompt}]}]}

      case http().post(
             "#{@gemini_url}#{model}:generateContent",
             [{"x-goog-api-key", key}],
             body,
             opts
           ) do
        {:ok, %{"candidates" => [%{"content" => %{"parts" => [%{"text" => text} | _]}} | _]}} ->
          {:ok, text}

        {:ok, other} ->
          {:error, {:unexpected, other}}

        error ->
          error
      end
    end
  end

  defp key(name) do
    case config(name) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, :not_configured}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp http, do: config(:http) || StarterKit.AI.HTTP

  defp config(key), do: Application.get_env(:starter_kit, __MODULE__, []) |> Keyword.get(key)
end
