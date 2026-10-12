defmodule Kaguya.Users.UserNotifier do
  import Swoosh.Email

  alias Kaguya.Mailer
  alias Kaguya.Users.User

  @from {"Kaguya", "accounts@kaguya.io"}

  def deliver_login_instructions(%User{} = user, url) do
    body = """
    Use this link to log in to Kaguya:

    #{url}

    The link expires in 15 minutes. If you didn't request it, you can ignore this email.
    """

    deliver(user.email, "Log in to Kaguya", body, login_html(url))
  end

  defp login_html(url) do
    escaped_url = url |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

    """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Log in to Kaguya</title>
      </head>
      <body style="margin: 0; background-color: #ffffff; color: #18181b; font-family: Arial, sans-serif;">
        <main style="max-width: 480px; margin: 0 auto; padding: 32px 24px;">
          <h1 style="margin: 0 0 24px; font-size: 24px;">Kaguya</h1>
          <p style="margin: 0 0 24px; line-height: 1.6;">Use this button to log in to Kaguya:</p>
          <p style="margin: 0 0 24px;">
            <a href="#{escaped_url}" style="display: inline-block; background-color: #18181b; color: #ffffff; padding: 14px 24px; border-radius: 6px; font-weight: bold; text-decoration: none;">Sign in to Kaguya</a>
          </p>
          <p style="margin: 0; line-height: 1.6;">The link expires in 15 minutes. If you didn't request it, you can ignore this email.</p>
        </main>
      </body>
    </html>
    """
  end

  def deliver_update_email_instructions(%User{} = user, new_email, url) do
    deliver(new_email, "Confirm your Kaguya email change", """
    Hi #{user.email},

    Use this link to confirm #{new_email} as your Kaguya email address:

    #{url}

    If you didn't request this change, you can ignore this email.
    """)
  end

  defp deliver(recipient, subject, body, html \\ nil) do
    email =
      new()
      |> to(recipient)
      |> from(@from)
      |> subject(subject)
      |> text_body(body)

    email = if html, do: html_body(email, html), else: email

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end
end
