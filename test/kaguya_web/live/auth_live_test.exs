defmodule KaguyaWeb.AuthLiveTest do
  use KaguyaWeb.ConnCase, async: false

  alias Kaguya.Test.UserFixtures
  alias Kaguya.Users

  test "renders login page with parity shell" do
    {:ok, _view, html} = live(build_conn(), "/login")

    assert html =~ "Welcome back"
    assert html =~ "Log in to your Kaguya account"
    assert html =~ "Email me a sign-in link"
    assert html =~ "towa@nitrochiral.com"
    assert html =~ "https://images.kaguya.io/ui/auth/auth.webp"
    assert html =~ ~s(href="/signup")
  end

  test "renders signup page with parity shell" do
    {:ok, _view, html} = live(build_conn(), "/signup")

    assert html =~ "Get started"
    assert html =~ "Create a new account"
    assert html =~ "Email me a sign-in link"
    assert html =~ "Already have an account?"
    assert html =~ "https://images.kaguya.io/ui/auth/auth.webp"
    assert html =~ ~s(href="/login")
  end

  test "renders password reset state" do
    {:ok, _view, html} = live(build_conn(), "/login?reset_password=true&action=forgot_password")

    assert html =~ "Sign in by email"
    assert html =~ "send you a sign-in link"
    assert html =~ ~s(action="/auth/reset-password")
  end

  test "login page patch links update password reset state" do
    {:ok, view, _html} = live(build_conn(), "/login?email=reader@example.com")

    html = render_patch(view, "/login?reset_password=true&action=forgot_password")

    assert_patch(view, "/login?reset_password=true&action=forgot_password")
    assert html =~ "Sign in by email"
    assert html =~ ~s(action="/auth/reset-password")
  end

  test "renders email confirmation state with signup email from session" do
    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{"signup_email" => "reader@example.com"})

    {:ok, _view, html} = live(conn, "/signup?action=confirm_email")

    assert html =~ "Check your email"
    assert html =~ "reader@example.com"
    assert html =~ ~s(action="/auth/resend-confirmation")
  end

  test "email confirmation state preserves stored setup return path" do
    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{
        "signup_email" => "reader@example.com",
        "signup_return_to" => "/vn/umineko"
      })

    {:ok, _view, html} = live(conn, "/signup?action=confirm_email")

    assert html =~ ~s(name="return_to")
    assert html =~ ~s(value="/vn/umineko")
  end

  test "account setup redirects anonymous visitors to signup" do
    assert {:error, {:redirect, %{to: "/signup"}}} =
             live(build_conn(), "/signup?action=account_setup")
  end

  test "account setup renders for users who need setup" do
    user = UserFixtures.insert_user!(%{username: nil, display_name: nil})

    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{"current_user_id" => user.id})

    {:ok, _view, html} = live(conn, "/signup?action=account_setup")

    assert html =~ "What should we call you?"
    assert html =~ "Pick a display name"
  end

  test "account setup remains available after profile basics are complete" do
    user = UserFixtures.insert_user!(%{username: "reader", display_name: "Reader"})

    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{"current_user_id" => user.id})

    {:ok, _view, html} = live(conn, "/signup?action=account_setup")

    assert html =~ "What should we call you?"
    assert html =~ "Reader"
  end

  test "account setup saves display name and advances to avatar step" do
    user = UserFixtures.insert_user!(%{username: nil, display_name: nil})

    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{"current_user_id" => user.id})

    {:ok, view, _html} = live(conn, "/signup?action=account_setup")

    html =
      view
      |> form("#account-setup-form", %{"setup" => %{"display_name" => "Reader"}})
      |> render_submit()

    assert html =~ "Add a profile picture"

    assert {:ok, updated} = Users.get_user(user.id)
    assert updated.display_name == "Reader"
    assert is_binary(updated.username)
  end

  test "account setup renders mobile and desktop skip controls on optional steps" do
    user = UserFixtures.insert_user!(%{username: nil, display_name: nil})

    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{"current_user_id" => user.id})

    {:ok, view, _html} = live(conn, "/signup?action=account_setup")

    view
    |> form("#account-setup-form", %{"setup" => %{"display_name" => "Reader"}})
    |> render_submit()

    assert has_element?(view, "#account-setup-skip")
    assert has_element?(view, "#account-setup-mobile-skip")
  end

  test "legacy password page redirects to account settings" do
    user = UserFixtures.insert_user!()

    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{"current_user_id" => user.id})

    assert {:error, {:redirect, %{to: "/account/settings"}}} =
             live(conn, "/account/edit/password")
  end
end
