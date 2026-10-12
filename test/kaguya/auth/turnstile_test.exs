defmodule Kaguya.Auth.TurnstileTest do
  use ExUnit.Case, async: false

  alias Kaguya.Auth.Turnstile

  test "posts to Siteverify without automatic retry and validates the configured action and hostname" do
    Req.Test.stub(:turnstile, fn conn ->
      assert conn.request_path == "/turnstile/v0/siteverify"
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      form = URI.decode_query(body)
      assert form["response"] == "valid-token"
      assert form["remoteip"] == "203.0.113.1"
      assert form["secret"] == Application.fetch_env!(:kaguya, :turnstile)[:secret_key]
      reply(conn, %{"success" => true, "hostname" => "localhost", "action" => "email_login"})
    end)

    assert :ok = Turnstile.verify("valid-token", "203.0.113.1")
  end

  test "missing, malformed and oversized tokens never call Cloudflare" do
    Req.Test.stub(:turnstile, fn _ -> flunk("invalid input reached Cloudflare") end)

    for token <- [nil, "", %{}, ["token"], String.duplicate("a", 2049)] do
      assert {:error, :missing_or_invalid_token} = Turnstile.verify(token, "203.0.113.1")
    end
  end

  for {body, reason} <- [
        {%{"success" => false, "error-codes" => ["invalid-input-response"]},
         :invalid_or_expired_token},
        {%{"success" => false, "error-codes" => ["timeout-or-duplicate"]},
         :invalid_or_expired_token},
        {%{"success" => "true"}, :invalid_or_expired_token},
        {%{"success" => true, "hostname" => "evil.example", "action" => "email_login"},
         :hostname_mismatch},
        {%{"success" => true, "hostname" => "localhost", "action" => "other_action"},
         :action_mismatch}
      ] do
    test "rejects #{reason} with #{inspect(body)}" do
      Req.Test.stub(:turnstile, &reply(&1, unquote(Macro.escape(body))))
      assert {:error, unquote(reason)} = Turnstile.verify("token", "203.0.113.1")
    end
  end

  test "service failures and malformed responses fail closed" do
    for body <- ["not-json", %{}, []] do
      Req.Test.stub(:turnstile, &reply(&1, body))
      assert {:error, _} = Turnstile.verify("token", "203.0.113.1")
    end

    Req.Test.stub(:turnstile, fn conn -> Plug.Conn.send_resp(conn, 503, "unavailable") end)
    assert {:error, :verification_unavailable} = Turnstile.verify("token", "203.0.113.1")

    Req.Test.stub(:turnstile, &Req.Test.transport_error(&1, :timeout))
    assert {:error, :verification_unavailable} = Turnstile.verify("token", "203.0.113.1")
  end

  test "missing configuration and production test keys fail closed" do
    previous = Application.fetch_env!(:kaguya, :turnstile)
    on_exit(fn -> Application.put_env(:kaguya, :turnstile, previous) end)
    Req.Test.stub(:turnstile, fn _ -> flunk("unconfigured verification reached Cloudflare") end)

    for overrides <- [[secret_key: nil], [hostnames: []], [allow_test_keys: false]] do
      Application.put_env(:kaguya, :turnstile, Keyword.merge(previous, overrides))
      assert {:error, :not_configured} = Turnstile.verify("token", "203.0.113.1")
    end
  end

  test "verification metrics contain only bounded outcomes and timing" do
    handler = "turnstile-test-#{System.unique_integer([:positive])}"
    :telemetry.attach(handler, [:kaguya, :auth, :turnstile, :stop], &__MODULE__.capture/4, self())
    on_exit(fn -> :telemetry.detach(handler) end)

    assert {:error, :missing_or_invalid_token} = Turnstile.verify(nil, "203.0.113.1")
    assert_receive {:verification, measurements, metadata}
    assert measurements.count == 1
    assert measurements.duration >= 0
    assert metadata == %{result: :rejected, reason: :missing_or_invalid_token}
  end

  test "Cloudflare's fixed dummy response is accepted only with an explicitly allowed test secret" do
    previous = Application.fetch_env!(:kaguya, :turnstile)
    on_exit(fn -> Application.put_env(:kaguya, :turnstile, previous) end)
    Req.Test.stub(:turnstile, &reply(&1, %{"success" => true, "hostname" => "example.com"}))

    assert :ok = Turnstile.verify("dummy-token", "203.0.113.1")

    Application.put_env(:kaguya, :turnstile, Keyword.put(previous, :secret_key, "real-secret"))
    assert {:error, :hostname_mismatch} = Turnstile.verify("dummy-token", "203.0.113.1")

    Application.put_env(:kaguya, :turnstile, Keyword.put(previous, :allow_test_keys, false))
    assert {:error, :not_configured} = Turnstile.verify("dummy-token", "203.0.113.1")
  end

  def capture(_event, measurements, metadata, owner) do
    send(owner, {:verification, measurements, metadata})
  end

  defp reply(conn, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(200, Jason.encode!(body))
  end
end
