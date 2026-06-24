defmodule KaguyaWeb.BrowserAuthControllerTest do
  use KaguyaWeb.ConnCase, async: false

  import ExUnit.CaptureLog

  alias Kaguya.Repo
  alias Kaguya.Test.UserFixtures
  alias Kaguya.Auth.OAuthState
  alias Kaguya.Users.{User, UserIdentity, UserToken}
  alias KaguyaWeb.UserAuth

  @session_max_age 60 * 60 * 24 * 90

  test "signup creates a local user and login token" do
    conn =
      build_conn()
      |> Map.put(:host, "localhost")
      |> Map.put(:port, 4000)
      |> post("/auth/sign-up", %{"email" => "reader@example.com"})

    assert redirected_to(conn) == "/signup?action=confirm_email"
    assert Plug.Conn.get_session(conn, "signup_email") == "reader@example.com"

    user = Repo.get_by!(User, email: "reader@example.com")
    assert user.email == "reader@example.com"
    assert user.username in [nil, ""]
    assert_login_token_for(user, "reader@example.com")
  end

  test "signup stores safe setup return path while awaiting confirmation" do
    conn =
      build_conn()
      |> post("/auth/sign-up", %{
        "email" => "reader@example.com",
        "return_to" => "/vn/umineko"
      })

    assert redirected_to(conn) == "/signup?action=confirm_email"
    assert Plug.Conn.get_session(conn, "signup_return_to") == "/vn/umineko"

    user = Repo.get_by!(User, email: "reader@example.com")
    assert_login_token_for(user, "reader@example.com")
  end

  test "signup rejects unsafe return path while awaiting confirmation" do
    conn =
      build_conn()
      |> post("/auth/sign-up", %{
        "email" => "reader@example.com",
        "return_to" => "//example.com/phish"
      })

    assert redirected_to(conn) == "/signup?action=confirm_email"
    assert Plug.Conn.get_session(conn, "signup_return_to") == "/"
  end

  test "magic-link confirmation preserves setup return path from link params" do
    conn =
      build_conn()
      |> post("/auth/sign-up", %{
        "email" => "reader@example.com",
        "return_to" => "/vn/umineko"
      })

    user = Repo.get_by!(User, email: "reader@example.com")
    token = insert_magic_link_token!(user)

    conn =
      conn
      |> recycle()
      |> get("/auth/confirm", %{"token" => token, "return_to" => "/vn/umineko"})

    assert_setup_redirect(conn, "/vn/umineko")
    assert is_binary(Plug.Conn.get_session(conn, "user_token"))
    assert conn.resp_cookies["_kaguya_key"].max_age == @session_max_age
  end

  test "login sends magic link and does not require Supabase credentials" do
    log =
      capture_log([level: :error], fn ->
        conn =
          build_conn()
          |> post("/auth/sign-in", %{"email" => "reader@example.com"})

        assert redirected_to(conn) == "/login?action=email_sent"
      end)

    refute log =~ "Supabase"

    user = Repo.get_by!(User, email: "reader@example.com")
    assert_login_token_for(user, "reader@example.com")
  end

  test "password reset entrypoint sends the same magic link" do
    conn =
      build_conn()
      |> Map.put(:host, "127.0.0.1")
      |> Map.put(:port, 4000)
      |> post("/auth/reset-password", %{"email" => "reader@example.com"})

    assert redirected_to(conn) == "/login?reset_password=true&action=email_sent"

    user = Repo.get_by!(User, email: "reader@example.com")
    assert_login_token_for(user, "reader@example.com")
  end

  test "change email sends a Phoenix-owned confirmation token" do
    user = UserFixtures.insert_user!(email: "reader@example.com")

    conn =
      logged_in_conn(user)
      |> post("/account/update-email", %{"email" => "new-reader@example.com"})

    assert redirected_to(conn) == "/account/edit/email"

    assert %UserToken{
             context: "change:reader@example.com",
             sent_to: "new-reader@example.com"
           } = Repo.get_by(UserToken, user_id: user.id, context: "change:reader@example.com")
  end

  test "change email rejects same email without creating a token" do
    user = UserFixtures.insert_user!(email: "reader@example.com")

    conn =
      logged_in_conn(user)
      |> post("/account/update-email", %{"email" => "reader@example.com"})

    assert redirected_to(conn) == "/account/edit/email"
    refute Repo.get_by(UserToken, user_id: user.id, context: "change:reader@example.com")
  end

  test "email-change confirmation updates local user email and issues a session" do
    user = UserFixtures.insert_user!(email: "reader@example.com")

    {token, user_token} =
      UserToken.build_email_token(user, "change:#{user.email}", "new@example.com")

    Repo.insert!(user_token)

    conn =
      build_conn()
      |> get("/auth/confirm", %{"type" => "email_change", "token" => token})

    assert redirected_to(conn) == "/account/edit/email"
    assert Repo.get!(User, user.id).email == "new@example.com"
    assert is_binary(Plug.Conn.get_session(conn, "user_token"))
    refute Repo.get_by(UserToken, user_id: user.id, context: "change:reader@example.com")
  end

  test "sign out deletes only the Phoenix session token" do
    user = UserFixtures.insert_user!()

    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{})
      |> UserAuth.log_in_user(user)

    token = Plug.Conn.get_session(conn, "user_token")
    assert Repo.get_by(UserToken, token: token, context: "session")

    conn = post(conn, "/auth/sign-out")

    assert redirected_to(conn) == "/"
    refute Repo.get_by(UserToken, token: token, context: "session")
  end

  test "google start redirects to Google and stashes return path with verifier" do
    conn =
      build_conn()
      |> get("/auth/google", %{"return_to" => "/vn/umineko"})

    assert conn.status == 302
    [location] = Plug.Conn.get_resp_header(conn, "location")
    uri = URI.parse(location)
    params = URI.decode_query(uri.query)

    assert uri.host == "accounts.google.com"
    assert params["client_id"] == "google_client_test"
    assert params["redirect_uri"] == "http://localhost:4002/auth/callback"
    assert params["scope"] == "openid email profile"
    assert params["code_challenge_method"] == "S256"
    assert is_binary(params["code_challenge"])

    assert {:ok, stash} = OAuthState.retrieve_and_delete(params["state"])
    assert stash.return_to == "/vn/umineko"
    assert stash.redirect_uri == "http://localhost:4002/auth/callback"
    assert is_binary(stash.verifier)
  end

  test "google callback logs in an existing linked identity" do
    user = UserFixtures.insert_user!()
    insert_google_identity!(user, provider_uid: "google-existing", email: user.email)
    state = store_google_state!("/members")

    stub_google_profile(%{
      "sub" => "google-existing",
      "email" => "different@example.com",
      "email_verified" => false
    })

    conn = get(build_conn(), "/auth/callback", %{"code" => "code", "state" => state})

    assert redirected_to(conn) == "/members"
    assert is_binary(Plug.Conn.get_session(conn, "user_token"))
  end

  test "google callback links a verified email to an existing local user" do
    user = UserFixtures.insert_user!(email: "reader@example.com")
    state = store_google_state!("/members")

    stub_google_profile(%{
      "sub" => "google-link",
      "email" => "Reader@Example.com",
      "email_verified" => true,
      "name" => "Reader",
      "picture" => "https://example.com/avatar.png"
    })

    conn = get(build_conn(), "/auth/callback", %{"code" => "code", "state" => state})

    assert redirected_to(conn) == "/members"

    assert %UserIdentity{
             user_id: user_id,
             provider: "google",
             provider_uid: "google-link",
             email: "reader@example.com",
             email_verified: true
           } = Repo.get_by(UserIdentity, provider: "google", provider_uid: "google-link")

    assert user_id == user.id
  end

  test "google callback creates a new local user with an explicit UUID" do
    state = store_google_state!("/vn/umineko")

    stub_google_profile(%{
      "sub" => "google-new",
      "email" => "new-reader@example.com",
      "email_verified" => true
    })

    conn = get(build_conn(), "/auth/callback", %{"code" => "code", "state" => state})

    assert_setup_redirect(conn, "/vn/umineko")

    user = Repo.get_by!(User, email: "new-reader@example.com")
    assert {:ok, _uuid} = Ecto.UUID.cast(user.id)
    assert user.username in [nil, ""]

    assert Repo.get_by!(UserIdentity, user_id: user.id, provider: "google").provider_uid ==
             "google-new"
  end

  test "google callback rejects unverified email when no identity exists" do
    state = store_google_state!("/members")

    stub_google_profile(%{
      "sub" => "google-unverified",
      "email" => "unverified@example.com",
      "email_verified" => false
    })

    conn = get(build_conn(), "/auth/callback", %{"code" => "code", "state" => state})

    assert redirected_to(conn) == "/login"
    refute Repo.get_by(User, email: "unverified@example.com")
    refute Repo.get_by(UserIdentity, provider: "google", provider_uid: "google-unverified")
  end

  test "google callback rejects duplicate provider linking for the matched email user" do
    user = UserFixtures.insert_user!(email: "reader@example.com")
    insert_google_identity!(user, provider_uid: "google-original", email: user.email)
    state = store_google_state!("/members")

    stub_google_profile(%{
      "sub" => "google-second",
      "email" => "reader@example.com",
      "email_verified" => true
    })

    conn = get(build_conn(), "/auth/callback", %{"code" => "code", "state" => state})

    assert redirected_to(conn) == "/login"
    refute Repo.get_by(UserIdentity, provider: "google", provider_uid: "google-second")
  end

  defp assert_login_token_for(user, sent_to) do
    assert %UserToken{context: "login", sent_to: ^sent_to} =
             Repo.get_by(UserToken, user_id: user.id, context: "login")
  end

  defp insert_magic_link_token!(user) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    encoded_token
  end

  defp logged_in_conn(user) do
    build_conn()
    |> Plug.Test.init_test_session(%{})
    |> UserAuth.log_in_user(user)
  end

  defp assert_setup_redirect(conn, return_to) do
    uri = conn |> redirected_to() |> URI.parse()
    query = URI.decode_query(uri.query || "")

    assert uri.path == "/signup"
    assert query["action"] == "account_setup"
    assert query["return_to"] == return_to
  end

  defp store_google_state!(return_to) do
    state = OAuthState.generate_state()

    assert {:ok, true} =
             OAuthState.store(state, %{
               verifier: "google_verifier_test",
               return_to: return_to,
               redirect_uri: "http://localhost:4002/auth/callback"
             })

    state
  end

  defp stub_google_profile(profile) do
    Req.Test.stub(:google_oauth, fn conn ->
      cond do
        conn.request_path == "/token" ->
          json(conn, 200, %{"access_token" => "google_access_token"})

        conn.request_path == "/v1/userinfo" ->
          json(conn, 200, profile)
      end
    end)
  end

  defp insert_google_identity!(user, attrs) do
    attrs =
      attrs
      |> Map.new()
      |> Map.merge(%{
        provider: "google",
        email_verified: true
      })

    %UserIdentity{user_id: user.id}
    |> UserIdentity.google_changeset(attrs)
    |> Repo.insert!()
  end

  defp json(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end
end
