defmodule StarterKitWeb.Plugs.ClientIp do
  @moduledoc """
  Sets `conn.remote_ip` to the real visitor (rate limits, audit events, session devices).

  Forwarding headers are trusted ONLY when the socket peer is a trusted proxy
  (`config :starter_kit, :trusted_proxy_cidrs`, env `TRUSTED_PROXY_CIDRS`; empty by
  default, so nothing is trusted). Then:

    * `X-Forwarded-For` is read right to left, skipping trusted proxies; the first other
      address is the peer that reached our proxy;
    * when that peer is a Cloudflare edge (`priv/network/cloudflare-cidrs.txt`, refresh with
      `mix starter_kit.cloudflare.refresh`), `CF-Connecting-IP` names the visitor.

  Anyone else can send these headers; they are ignored. IPv4-mapped IPv6 peers are
  normalized to IPv4. The result also goes to `StarterKit.Audit.put_request_ip/1`.
  """

  @behaviour Plug

  import Plug.Conn

  alias RemoteIp.Block

  @external_resource "priv/network/cloudflare-cidrs.txt"
  @cloudflare @external_resource |> File.read!() |> String.split() |> Enum.map(&Block.parse!/1)

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, opts) do
    proxies =
      opts
      |> Keyword.get_lazy(:trusted_proxies, fn ->
        Application.get_env(:starter_kit, :trusted_proxy_cidrs, [])
      end)
      |> Enum.map(&Block.parse!/1)

    socket_peer = normalize(conn.remote_ip)
    trusted? = member?(socket_peer, proxies)
    peer = if trusted?, do: forwarded_peer(conn, proxies) || socket_peer, else: socket_peer

    visitor =
      if trusted? and member?(peer, @cloudflare),
        do: connecting_ip(conn) || peer,
        else: peer

    StarterKit.Audit.put_request_ip(visitor |> :inet.ntoa() |> to_string())
    %{conn | remote_ip: visitor}
  end

  # The rightmost address that is not one of our proxies.
  defp forwarded_peer(conn, proxies) do
    with [value] when byte_size(value) <= 2048 <- get_req_header(conn, "x-forwarded-for"),
         chain = value |> String.split(",") |> Enum.map(&parse/1),
         true <- length(chain) <= 20 and Enum.all?(chain) do
      chain |> Enum.reverse() |> Enum.find(&(not member?(&1, proxies)))
    else
      _ -> nil
    end
  end

  defp connecting_ip(conn) do
    case get_req_header(conn, "cf-connecting-ip") do
      [value] -> parse(value)
      _ -> nil
    end
  end

  defp parse(value) when byte_size(value) <= 45 do
    case value |> String.trim() |> String.to_charlist() |> :inet.parse_strict_address() do
      {:ok, ip} -> normalize(ip)
      _ -> nil
    end
  end

  defp parse(_), do: nil

  defp normalize({0, 0, 0, 0, 0, 0xFFFF, high, low}),
    do: {Bitwise.bsr(high, 8), Bitwise.band(high, 255), Bitwise.bsr(low, 8), Bitwise.band(low, 255)}

  defp normalize(ip), do: ip

  defp member?(ip, blocks), do: Enum.any?(blocks, &Block.contains?(&1, Block.encode(ip)))
end
