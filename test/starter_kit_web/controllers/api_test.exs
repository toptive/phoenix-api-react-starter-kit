defmodule StarterKitWeb.ApiTest do
  use StarterKitWeb.ConnCase, async: true

  test "direct uploads need a session and answer in the envelope", %{conn: conn} do
    conn = put_req_header(conn, "accept", "application/json")

    assert %{"error" => %{"code" => "unauthorized"}} =
             conn |> post(~p"/api/v1/direct-uploads", %{}) |> json_response(401)

    %{conn: conn} = register_and_log_in_user(%{conn: conn})

    body = %{
      "direct_upload" => %{
        "filename" => "a.png",
        "content_type" => "image/png",
        "byte_size" => 10,
        "kind" => "image"
      }
    }

    assert %{"data" => %{"url" => url, "key" => _}} =
             conn |> post(~p"/api/v1/direct-uploads", body) |> json_response(201)

    assert url =~ "storage.example.com"

    bad = put_in(body, ["direct_upload", "content_type"], "image/svg+xml")

    assert %{"error" => %{"code" => "content_type_not_allowed", "message" => message}} =
             conn |> post(~p"/api/v1/direct-uploads", bad) |> json_response(422)

    assert message =~ "not allowed"
  end

  test "client analytics events accept only client events", %{conn: conn} do
    conn = conn |> init_test_session(%{}) |> put_req_header("accept", "application/json")

    assert conn
           |> post(~p"/api/v1/events", %{
             "event" => %{
               "name" => "page_viewed",
               "properties" => %{"page" => "home.show", "path" => "/?q=x"}
             }
           })
           |> json_response(202)

    # Anonymous: a random id per event and no person profile. Undeclared props are dropped.
    assert_received {:analytics, %{event: "page_viewed", distinct_id: id, properties: props}}
    assert {:ok, _} = Ecto.UUID.cast(id)
    assert props == %{"page" => "home.show", "$process_person_profile" => false}
  end
end
