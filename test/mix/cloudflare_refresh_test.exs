defmodule Mix.Tasks.StarterKit.Cloudflare.RefreshTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.StarterKit.Cloudflare.Refresh

  @v4 "173.245.48.0/20\n103.21.244.0/22\n"
  @v6 "2400:cb00::/32\n"

  setup do
    path = Path.join(System.tmp_dir!(), "cf-#{Base.url_encode64(:crypto.strong_rand_bytes(9))}.txt")
    File.write!(path, "old\n")
    on_exit(fn -> File.rm(path) end)
    %{path: path}
  end

  defp fetch(v4, v6) do
    fn
      "https://www.cloudflare.com/ips-v4", _opts -> {:ok, %{status: 200, body: v4}}
      "https://www.cloudflare.com/ips-v6", _opts -> {:ok, %{status: 200, body: v6}}
    end
  end

  test "replaces the file when both lists validate", %{path: path} do
    assert {:ok, %{ipv4: 2, ipv6: 1}} = Refresh.refresh(path, fetch(@v4, @v6))
    assert File.read!(path) == "173.245.48.0/20\n103.21.244.0/22\n2400:cb00::/32\n"
  end

  test "keeps the file on private, wrong-family or duplicate ranges", %{path: path} do
    for {v4, v6} <- [
          {"10.0.0.0/8\n", @v6},
          {@v4, "173.245.48.0/20\n"},
          {"173.245.48.0/20\n173.245.48.0/20\n", @v6},
          {"", @v6}
        ] do
      assert {:error, :invalid_cloudflare_ranges} = Refresh.refresh(path, fetch(v4, v6))
    end

    assert File.read!(path) == "old\n"
  end
end
