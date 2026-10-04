defmodule StarterKitWeb.ApiPlatformTest do
  use StarterKitWeb.ConnCase, async: false
  import StarterKitWeb.ApiHelpers
  alias StarterKit.{Accounts, Uploads}

  setup %{conn: conn} do
    original = Application.get_env(:starter_kit, Uploads)
    on_exit(fn -> Application.put_env(:starter_kit, Uploads, original) end)
    conn = api_conn(conn)
    scope = scope_fixture()
    %{conn: conn, scope: scope, auth: bearer(conn, Accounts.generate_api_token(scope.user).token)}
  end

  test "presign accepts each kind, fixes the type, scopes the key and expires in ten minutes", %{
    auth: auth,
    scope: scope
  } do
    for {kind, type, size} <- [
          {"image", "image/gif", 10_000_000},
          {"document", "application/pdf", 20_000_000},
          {"avatar", "image/webp", 2_000_000}
        ] do
      before = DateTime.utc_now(:second)

      result =
        post(auth, ~p"/api/v1/direct-uploads", %{
          filename: "../../My File.PDF",
          contentType: type,
          byteSize: size,
          kind: kind,
          organizationId: Ecto.UUID.generate()
        })

      upload = json_response(result, 201)["data"]
      assert Map.keys(upload) |> Enum.sort() == ~w(expiresAt headers key url)
      assert upload["key"] =~ "uploads/#{scope.organization.id}/"
      assert upload["key"] =~ "my-file.pdf"
      refute upload["key"] =~ ".."
      assert upload["headers"] == %{"content-type" => type}
      query = URI.parse(upload["url"]).query |> URI.decode_query()
      assert query["X-Amz-Expires"] == "600"
      assert query["X-Amz-SignedHeaders"] =~ "content-type"
      assert query["X-Amz-Signature"]
      {:ok, expiry, 0} = DateTime.from_iso8601(upload["expiresAt"])
      assert DateTime.diff(expiry, before) in 600..601
      assert get_resp_header(result, "set-cookie") == []
    end
  end

  test "uploads need a bearer and signed-in users receive their own organization prefix", %{
    conn: conn
  } do
    assert_error(post(conn, ~p"/api/v1/direct-uploads", upload()), 401, "unauthorized")
    scope = scope_fixture()
    issued = Accounts.generate_api_token(scope.user)
    result = post(bearer(conn, issued.token), ~p"/api/v1/direct-uploads", upload())
    assert json_response(result, 201)["data"]["key"] =~ "uploads/#{scope.organization.id}/"
  end

  test "presign refuses SVG and kind/type/size violations", %{auth: auth} do
    for {change, code} <- [
          {%{contentType: "image/svg+xml"}, "content_type_not_allowed"},
          {%{kind: "avatar", contentType: "image/gif"}, "content_type_not_allowed"},
          {%{kind: "document", contentType: "image/webp"}, "content_type_not_allowed"},
          {%{byteSize: 10_000_001}, "too_large"},
          {%{kind: "avatar", byteSize: 2_000_001}, "too_large"},
          {%{kind: "document", contentType: "application/pdf", byteSize: 20_000_001}, "too_large"},
          {%{byteSize: 0}, "invalid_size"},
          {%{byteSize: -1}, "invalid_size"},
          {%{byteSize: 1.5}, "invalid_size"},
          {%{byteSize: "10"}, "invalid_size"},
          {%{kind: "video"}, "unknown_kind"}
        ] do
      assert_error(post(auth, ~p"/api/v1/direct-uploads", Map.merge(upload(), change)), 422, code)
    end

    for params <- [%{}, %{directUpload: upload()}, Map.put(upload(), :filename, [])],
        do: assert_error(post(auth, ~p"/api/v1/direct-uploads", params), 400, "bad_request")
  end

  test "unconfigured object storage returns 503", %{auth: auth} do
    Application.put_env(:starter_kit, Uploads, [])
    assert_error(post(auth, ~p"/api/v1/direct-uploads", upload()), 503, "uploads_not_configured")
  end

  test "presign → storage verification accepts bytes and refuses incomplete, oversized or mismatched objects",
       %{auth: auth, scope: scope} do
    Application.put_env(:starter_kit, Uploads,
      bucket: "test-bucket",
      request_options: [http_opts: [plug: {Req.Test, Uploads}], retries: [max_attempts: 1]]
    )

    key = json_response(post(auth, ~p"/api/v1/direct-uploads", upload()), 201)["data"]["key"]
    png = <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, "image">>

    for {size, bytes, expected} <- [
          {100, png, :ok},
          {0, png, {:error, :upload_incomplete}},
          {10_000_001, png, {:error, :upload_incomplete}},
          {100, "<svg xmlns=", {:error, :upload_incomplete}},
          {100, "%PDF-", {:error, :upload_incomplete}}
        ] do
      Req.Test.stub(Uploads, fn conn ->
        assert conn.request_path =~ key

        if conn.method == "HEAD" do
          conn |> put_resp_header("content-length", to_string(size)) |> send_resp(200, "")
        else
          assert get_req_header(conn, "range") == ["bytes=0-15"]
          send_resp(conn, 200, bytes)
        end
      end)

      assert Uploads.verify(scope, key, "image") == expected
    end

    Req.Test.stub(Uploads, &send_resp(&1, 404, ""))
    assert Uploads.verify(scope, key, "image") == {:error, :upload_incomplete}
    Req.Test.stub(Uploads, fn _ -> flunk("A foreign key must not reach storage") end)
    assert Uploads.verify(scope_fixture(), key, "image") == {:error, :upload_incomplete}

    assert Uploads.verify(scope, "uploads/#{scope.organization.id}/../foreign", "image") ==
             {:error, :upload_incomplete}
  end

  test "uploads rate limit at 60 per minute", %{auth: auth} do
    for _ <- 1..60, do: assert(json_response(post(auth, ~p"/api/v1/direct-uploads", upload()), 201))
    limited = post(auth, ~p"/api/v1/direct-uploads", upload())
    assert_error(limited, 429, "rate_limited")
    assert get_resp_header(limited, "retry-after") != []
  end

  test "client events are public, typed, cookie-free and anonymous without a bearer", %{conn: conn} do
    result =
      post(conn, ~p"/api/v1/events", %{
        name: "page_viewed",
        properties: %{page: "home.show", email: "private@example.com"}
      })

    assert json_response(result, 202)["data"] == %{"accepted" => true}
    assert get_resp_header(result, "set-cookie") == []
    assert_received {:analytics, %{event: "page_viewed", distinct_id: id, properties: props}}
    assert {:ok, _} = Ecto.UUID.cast(id)
    assert props == %{"page" => "home.show", "$process_person_profile" => false}
    post(conn, ~p"/api/v1/events", %{name: "page_viewed"}) |> json_response(202)
    assert_received {:analytics, %{distinct_id: next}}
    refute next == id
  end

  test "events with a bearer use the actor and drop invalid and undeclared properties", %{
    auth: auth,
    scope: scope
  } do
    post(auth, ~p"/api/v1/events", %{
      name: "cta_clicked",
      properties: %{cta: "buy", page: "settings.billing", secret: "x"}
    })
    |> json_response(202)

    id = scope.user.id

    assert_received {:analytics,
                     %{
                       event: "cta_clicked",
                       distinct_id: ^id,
                       properties: %{"cta" => "buy", "page" => "settings.billing"}
                     }}

    for properties <- [
          %{cta: "private@example.com", page: String.duplicate("x", 81)},
          [],
          "invalid"
        ] do
      post(auth, ~p"/api/v1/events", %{name: "cta_clicked", properties: properties})
      |> json_response(202)

      assert_received {:analytics, %{properties: props}}
      assert props == %{}
    end
  end

  test "unknown and server-only client event names are silently acknowledged", %{conn: conn} do
    for name <- ["made_up", "user_registered", "subscription_started", "public_page_viewed"] do
      assert json_response(post(conn, ~p"/api/v1/events", %{name: name}), 202)["data"] == %{
               "accepted" => true
             }

      refute_received {:analytics, _}
    end

    for params <- [%{}, %{name: []}, %{event: %{name: "page_viewed"}}],
        do: assert_error(post(conn, ~p"/api/v1/events", params), 400, "bad_request")
  end

  test "events rate limit at 120 per minute", %{conn: conn} do
    for _ <- 1..120,
        do: assert(json_response(post(conn, ~p"/api/v1/events", %{name: "unknown"}), 202))

    limited = post(conn, ~p"/api/v1/events", %{name: "unknown"})
    assert_error(limited, 429, "rate_limited")
    assert get_resp_header(limited, "retry-after") != []
  end

  defp upload,
    do: %{filename: "My Photo.PNG", contentType: "image/png", byteSize: 100, kind: "image"}
end
