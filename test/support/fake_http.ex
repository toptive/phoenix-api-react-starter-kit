defmodule StarterKit.AI.FakeHTTP do
  @moduledoc "Test double for AI providers: answers from the process dictionary."

  use Boundary, top_level?: true, check: [in: false, out: false]

  def post(url, _headers, body, _opts) do
    send(self(), {:ai_request, url, body})

    case Process.get(:ai_response) do
      nil -> {:ok, %{"choices" => [%{"message" => %{"content" => "{}"}}]}}
      fun when is_function(fun, 1) -> fun.(body)
      response -> response
    end
  end
end
