defmodule StarterKitWeb.Plugs.ClientIpTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias StarterKitWeb.Plugs.ClientIp

  @proxy {172, 18, 0, 5}
  @proxies ["172.18.0.0/16"]
  @cloudflare_edge "104.16.0.10"

  defp visitor(peer, headers, proxies \\ @proxies) do
    conn =
      Enum.reduce(headers, %{conn(:get, "/") | remote_ip: peer}, fn {k, v}, conn ->
        Plug.Conn.put_req_header(conn, k, v)
      end)

    conn
    |> ClientIp.call(trusted_proxies: proxies)
    |> Map.fetch!(:remote_ip)
    |> :inet.ntoa()
    |> to_string()
  end

  test "without trusted proxies, forwarding headers are ignored" do
    assert visitor(@proxy, [{"x-forwarded-for", "203.0.113.7"}], []) == "172.18.0.5"
  end

  test "an untrusted peer cannot spoof its address" do
    headers = [{"x-forwarded-for", "203.0.113.7"}, {"cf-connecting-ip", "203.0.113.8"}]
    assert visitor({198, 51, 100, 1}, headers) == "198.51.100.1"
  end

  test "behind the trusted proxy, the rightmost other X-Forwarded-For address wins" do
    assert visitor(@proxy, [{"x-forwarded-for", "203.0.113.7"}]) == "203.0.113.7"
    # The client may prepend anything; only the hop our proxy appended counts.
    assert visitor(@proxy, [{"x-forwarded-for", "1.2.3.4, 203.0.113.7"}]) == "203.0.113.7"
  end

  test "CF-Connecting-IP counts only when the hop before our proxy is a Cloudflare edge" do
    via_cloudflare = [{"x-forwarded-for", @cloudflare_edge}, {"cf-connecting-ip", "203.0.113.9"}]
    assert visitor(@proxy, via_cloudflare) == "203.0.113.9"

    direct = [{"x-forwarded-for", "198.51.100.2"}, {"cf-connecting-ip", "203.0.113.9"}]
    assert visitor(@proxy, direct) == "198.51.100.2"
  end

  test "a malformed chain falls back to the socket peer" do
    assert visitor(@proxy, [{"x-forwarded-for", "203.0.113.7, not-an-ip"}]) == "172.18.0.5"
    assert visitor(@proxy, [{"x-forwarded-for", String.duplicate("1.1.1.1,", 300)}]) == "172.18.0.5"
  end

  test "IPv4-mapped IPv6 addresses become IPv4" do
    assert visitor({0, 0, 0, 0, 0, 0xFFFF, 0xCB00, 0x7107}, []) == "203.0.113.7"
    assert visitor(@proxy, [{"x-forwarded-for", "::ffff:203.0.113.7"}]) == "203.0.113.7"
  end

  test "the visitor IP reaches audit events of this request" do
    visitor(@proxy, [{"x-forwarded-for", "203.0.113.7"}])
    assert Process.get({StarterKit.Audit, :request_ip}) == "203.0.113.7"
  end
end
