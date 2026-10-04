defmodule Mix.Tasks.StarterKit.Cloudflare.Refresh do
  @moduledoc """
  Refreshes `priv/network/cloudflare-cidrs.txt` (the Cloudflare edge ranges that
  `StarterKitWeb.Plugs.ClientIp` trusts) from the official lists. Review the diff and
  commit it; the file is read at compile time.

      mix starter_kit.cloudflare.refresh

  Both lists must download and validate (public ranges only, no duplicates), or the file
  stays unchanged.
  """
  @shortdoc "Refreshes the vendored Cloudflare edge ranges"

  use Mix.Task
  use Boundary, top_level?: true, deps: []

  alias RemoteIp.Block

  @path "priv/network/cloudflare-cidrs.txt"

  @reserved ~w(0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12
    192.0.0.0/24 192.0.2.0/24 192.168.0.0/16 198.18.0.0/15 198.51.100.0/24 203.0.113.0/24
    224.0.0.0/4 240.0.0.0/4 2001:db8::/32)

  @impl true
  def run([]) do
    Application.ensure_all_started(:req)

    case refresh(@path) do
      {:ok, counts} -> Mix.shell().info("Cloudflare ranges refreshed: #{inspect(counts)}")
      {:error, reason} -> Mix.raise("Cloudflare ranges unchanged: #{reason}")
    end
  end

  def run(_), do: Mix.raise("Usage: mix starter_kit.cloudflare.refresh")

  @doc "Downloads both lists and replaces `path` only when both validate."
  def refresh(path, fetch \\ &Req.get/2) do
    with {:ok, v4} <- fetch_ranges(fetch, :v4),
         {:ok, v6} <- fetch_ranges(fetch, :v6) do
      temporary = "#{path}.#{Base.url_encode64(:crypto.strong_rand_bytes(9))}.tmp"

      try do
        File.write!(temporary, Enum.join(v4 ++ v6, "\n") <> "\n", [:exclusive])
        File.rename!(temporary, path)
        {:ok, %{ipv4: length(v4), ipv6: length(v6)}}
      after
        File.rm(temporary)
      end
    end
  end

  defp fetch_ranges(fetch, family) do
    url = "https://www.cloudflare.com/ips-#{family}"

    with {:ok, %{status: 200, body: body}} when is_binary(body) and byte_size(body) <= 16_384 <-
           fetch.(url, redirect: false, retry: false, decode_body: false, receive_timeout: 15_000),
         lines = String.split(body),
         true <- length(lines) in 1..256 and length(Enum.uniq(lines)) == length(lines),
         true <- Enum.all?(lines, &public_range?(&1, family)) do
      {:ok, lines}
    else
      _ -> {:error, :invalid_cloudflare_ranges}
    end
  end

  defp public_range?(cidr, family) do
    case Block.parse(cidr) do
      {:ok, %Block{proto: ^family} = block} ->
        to_string(block) == String.downcase(cidr) and not reserved?(block)

      _ ->
        false
    end
  end

  defp reserved?(block) do
    Enum.any?(@reserved, fn cidr ->
      reserved = Block.parse!(cidr)

      Block.contains?(block, {reserved.proto, reserved.net}) or
        Block.contains?(reserved, {block.proto, block.net})
    end)
  end
end
