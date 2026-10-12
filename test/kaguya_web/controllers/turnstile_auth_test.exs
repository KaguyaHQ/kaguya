defmodule KaguyaWeb.TurnstileAuthTest do
  use KaguyaWeb.ConnCase, async: false

  import Swoosh.TestAssertions
  import ExUnit.CaptureLog

  alias Kaguya.Repo
  alias Kaguya.Test.UserFixtures
  alias Kaguya.Users.{User, UserToken}

  @routes [
    {"/auth/sign-up", "/signup"},
    {"/auth/sign-in", "/login"},
    {"/auth/verify-email", "/signup"},
    {"/auth/resend-confirmation", "/signup"},
    {"/auth/reset-password", "/login"}
  ]

  setup do
    :sys.replace_state(Kaguya.Auth.EmailRateLimit, fn table ->
      :ets.delete_all_objects(table)
      table
    end)

    :ok
  end

  test "all email routes share the recipient cooldown across IPs and normalized addresses" do
    stub_verification(true)

    assert post(magic_conn(), "/auth/sign-up", params()) |> redirected_to() ==
             "/signup?action=confirm_email"

    assert_email_sent(subject: "Log in to Kaguya")

    for {path, _retry_path} <- @routes do
      request = Map.put(params(), "email", "  READER@EXAMPLE.COM  ")
      conn = post(magic_conn(), path, request)
      assert Phoenix.Flash.get(conn.assigns.flash, :auth_error) =~ "seconds"
      assert Repo.aggregate(UserToken, :count) == 1
      refute_email_sent()
    end
  end

  test "an invalid challenge cannot consume the recipient cooldown" do
    stub_verification(false)
    post(magic_conn(), "/auth/sign-up", params())
    refute_email_sent()
    stub_verification(true)
    conn = post(magic_conn(), "/auth/sign-up", params())
    assert redirected_to(conn) == "/signup?action=confirm_email"
    assert_email_sent(subject: "Log in to Kaguya")
  end

  test "concurrent requests with different valid challenges send only one email to the recipient" do
    stub_verification(true)
    owner = self()

    tasks =
      for i <- 1..2 do
        Task.async(fn ->
          Req.Test.allow(:turnstile, owner, self())
          send(owner, {:ready, self()})

          receive do
            :go ->
              post(
                magic_conn(),
                "/auth/sign-up",
                Map.put(params(), "cf-turnstile-response", "valid-#{i}")
              )
              |> redirected_to()
          end
        end)
      end

    ready =
      for _ <- tasks do
        assert_receive {:ready, pid}
        pid
      end

    Enum.each(ready, &send(&1, :go))
    destinations = Enum.map(tasks, &Task.await/1)
    assert Enum.count(destinations, &(&1 == "/signup?action=confirm_email")) == 1
    assert Repo.aggregate(UserToken, :count) == 1
    assert_email_sent(subject: "Log in to Kaguya")
    refute_email_sent()
  end

  for {path, retry_path} <- @routes do
    test "#{path} rejects missing verification before creating an account or token" do
      Req.Test.stub(:turnstile, fn _ -> flunk("missing token reached Cloudflare") end)
      conn = post(magic_conn(), unquote(path), %{"email" => "reader@example.com"})
      assert URI.parse(redirected_to(conn)).path == unquote(retry_path)
      assert Phoenix.Flash.get(conn.assigns.flash, :auth_error)
      refute Repo.get_by(User, email: "reader@example.com")
      assert Repo.aggregate(UserToken, :count) == 0
      refute_email_sent()
    end

    test "#{path} rejects invalid verification for an existing user without sending" do
      user = UserFixtures.insert_user!(email: "reader@example.com")
      stub_verification(false)
      conn = post(magic_conn(), unquote(path), params())
      assert URI.parse(redirected_to(conn)).path == unquote(retry_path)
      assert Repo.get!(User, user.id).email == user.email
      refute Repo.get_by(UserToken, user_id: user.id)
      refute_email_sent()
    end
  end

  test "verified signup creates one user, sends a link, and preserves onboarding destination" do
    stub_verification(true)
    conn = post(magic_conn(), "/auth/sign-up", Map.put(params(), "return_to", "/vn/umineko"))
    assert redirected_to(conn) == "/signup?action=confirm_email"
    assert get_session(conn, "signup_return_to") == "/vn/umineko"
    user = Repo.get_by!(User, email: "reader@example.com")
    assert Repo.get_by(UserToken, user_id: user.id, context: "login")
    assert_email_sent(subject: "Log in to Kaguya")
  end

  test "verified login reuses an existing account" do
    user = UserFixtures.insert_user!(email: "reader@example.com")
    stub_verification(true)
    conn = post(magic_conn(), "/auth/sign-in", params())
    assert redirected_to(conn) == "/login?action=email_sent"
    assert Repo.get_by!(User, email: user.email).id == user.id
    assert Repo.get_by(UserToken, user_id: user.id, context: "login")
    assert_email_sent(subject: "Log in to Kaguya")
  end

  test "a replayed challenge cannot send a second email" do
    used = start_supervised!({Agent, fn -> false end})
    stub_single_use(used)

    assert post(magic_conn(), "/auth/sign-up", params()) |> redirected_to() ==
             "/signup?action=confirm_email"

    assert_email_sent(subject: "Log in to Kaguya")

    conn = post(magic_conn(), "/auth/sign-in", params())
    assert URI.parse(redirected_to(conn)).path == "/login"
    assert Repo.aggregate(UserToken, :count) == 1
    refute_email_sent()
  end

  test "concurrent replay of a challenge admits at most one send" do
    used = start_supervised!({Agent, fn -> false end})
    stub_single_use(used)
    owner = self()

    tasks =
      for _ <- 1..2 do
        Task.async(fn ->
          Req.Test.allow(:turnstile, owner, self())
          send(owner, {:ready, self()})

          receive do
            :go -> post(magic_conn(), "/auth/sign-up", params()) |> redirected_to()
          end
        end)
      end

    ready =
      for _ <- tasks do
        assert_receive {:ready, pid}
        pid
      end

    Enum.each(ready, &send(&1, :go))

    destinations = Enum.map(tasks, &Task.await/1)
    assert Enum.count(destinations, &(&1 == "/signup?action=confirm_email")) == 1
    assert Repo.aggregate(User, :count) == 1
    assert Repo.aggregate(UserToken, :count) == 1
  end

  test "verification failures log only a bounded reason and filter sensitive request parameters" do
    stub_verification(false)
    log = capture_log(fn -> post(magic_conn(), "/auth/sign-up", params()) end)
    refute log =~ "reader@example.com"
    refute log =~ "challenge-secret-token"

    filtered = Phoenix.Logger.filter_values(params())
    assert filtered["email"] == "[FILTERED]"
    assert filtered["cf-turnstile-response"] == "[FILTERED]"
  end

  defp params do
    %{"email" => "reader@example.com", "cf-turnstile-response" => "challenge-secret-token"}
  end

  defp magic_conn do
    build_conn()
    |> put_req_header("cf-connecting-ip", "test-#{System.unique_integer([:positive])}")
  end

  defp stub_verification(success) do
    Req.Test.stub(:turnstile, &reply(&1, success))
  end

  defp stub_single_use(used) do
    Req.Test.stub(:turnstile, fn conn ->
      success = Agent.get_and_update(used, fn previous -> {not previous, true} end)
      reply(conn, success)
    end)
  end

  defp reply(conn, success) do
    body = %{
      "success" => success,
      "hostname" => "localhost",
      "action" => "email_login",
      "error-codes" => if(success, do: [], else: ["timeout-or-duplicate"])
    }

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(body))
  end
end
