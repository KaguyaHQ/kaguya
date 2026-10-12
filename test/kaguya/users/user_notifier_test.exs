defmodule Kaguya.Users.UserNotifierTest do
  use ExUnit.Case, async: true

  import Swoosh.TestAssertions

  alias Kaguya.Users.{User, UserNotifier}

  test "login email offers the same sign-in link in HTML and plain text" do
    user = %User{email: "reader@example.com"}
    url = "https://kaguya.io/auth/confirm?token=example-token&return_to=%2F"

    assert {:ok, email} = UserNotifier.deliver_login_instructions(user, url)
    assert_email_sent(email)
    assert email.text_body =~ url
    refute email.text_body =~ user.email

    html = Floki.parse_document!(email.html_body)
    assert Floki.find(html, "a") |> Floki.attribute("href") == [url]
    assert Floki.find(html, "a") |> Floki.text() == "Sign in to Kaguya"
    refute Floki.text(html) =~ user.email
    assert Floki.text(html) =~ "expires in 15 minutes"
  end

  test "HTML escapes characters in the sign-in URL" do
    url = "https://kaguya.io/auth/confirm?token=example&return_to=\"<example>"

    assert {:ok, email} =
             UserNotifier.deliver_login_instructions(%User{email: "reader@example.com"}, url)

    html = Floki.parse_document!(email.html_body)
    assert Floki.find(html, "a") |> Floki.attribute("href") == [url]
    assert Floki.find(html, "example") == []
  end
end
