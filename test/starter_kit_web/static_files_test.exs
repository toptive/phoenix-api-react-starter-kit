defmodule StarterKitWeb.StaticFilesTest do
  use StarterKitWeb.ConnCase, async: true

  # Every root file the endpoint promises to serve exists (no 404 for a browser's
  # /favicon.ico or an iPhone's /apple-touch-icon.png).
  test "every static root file is served", %{conn: conn} do
    for path <- StarterKitWeb.static_paths(), String.contains?(path, ".") do
      assert get(conn, "/" <> path).status == 200, "/#{path} is missing from priv/static"
    end
  end

  test "the web app manifest lists icons that exist", %{conn: conn} do
    conn = get(conn, "/site.webmanifest")
    manifest = Jason.decode!(conn.resp_body)

    assert manifest["name"] == Application.fetch_env!(:starter_kit, :app_name)

    for %{"src" => src, "sizes" => sizes} <- manifest["icons"] do
      [width, height] = sizes |> String.split("x") |> Enum.map(&String.to_integer/1)
      <<_::binary-size(16), w::32, h::32, _::binary>> = File.read!("priv/static" <> src)
      assert {w, h} == {width, height}, "#{src} is #{w}x#{h}, the manifest says #{sizes}"
    end
  end
end
