defmodule KaguyaWeb.SentryTunnelControllerTest do
  use KaguyaWeb.ConnCase, async: false

  @valid_dsn "https://abc123@o4508216.ingest.us.sentry.io/4508216401002496"

  setup do
    prior = Application.get_env(:kaguya, :sentry_browser, [])

    Application.put_env(:kaguya, :sentry_browser,
      dsn: @valid_dsn,
      environment: "test",
      release: "test-release"
    )

    on_exit(fn -> Application.put_env(:kaguya, :sentry_browser, prior) end)
  end

  describe "POST /_sen_tunnel" do
    test "rejects an empty body", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/x-sentry-envelope")
        |> post("/_sen_tunnel", "")

      assert conn.status == 400
    end

    test "rejects a body whose first line isn't valid envelope JSON", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/x-sentry-envelope")
        |> post("/_sen_tunnel", "not json\n{}\n")

      assert conn.status == 400
    end

    test "rejects an envelope without a `dsn` field", %{conn: conn} do
      body = ~s({"event_id":"x","sent_at":"y"}\n{"type":"event"}\n{})

      conn =
        conn
        |> put_req_header("content-type", "application/x-sentry-envelope")
        |> post("/_sen_tunnel", body)

      assert conn.status == 400
    end

    test "rejects an envelope whose DSN doesn't match the configured browser DSN", %{conn: conn} do
      body =
        ~s({"event_id":"x","sent_at":"y","dsn":"https://other@evil.example/9"}\n{"type":"event"}\n{})

      conn =
        conn
        |> put_req_header("content-type", "application/x-sentry-envelope")
        |> post("/_sen_tunnel", body)

      assert conn.status == 400
    end

    # Forward-success path requires hitting the real Sentry endpoint; not
    # something we want as a unit test. We verify the validation gate above
    # is the bottleneck — anything past it is straight-line Finch.
  end
end
