defmodule Kaguya.Users.UserNotifier do
  import Swoosh.Email

  alias Kaguya.Mailer
  alias Kaguya.Users.User

  @from {"Kaguya", "accounts@kaguya.io"}

  def deliver_login_instructions(%User{} = user, url) do
    deliver(user.email, "Log in to Kaguya", """
    Hi #{user.email},

    Use this link to log in to Kaguya:

    #{url}

    The link expires in 15 minutes. If you didn't request it, you can ignore this email.
    """)
  end

  def deliver_update_email_instructions(%User{} = user, new_email, url) do
    deliver(new_email, "Confirm your Kaguya email change", """
    Hi #{user.email},

    Use this link to confirm #{new_email} as your Kaguya email address:

    #{url}

    If you didn't request this change, you can ignore this email.
    """)
  end

  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from(@from)
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end
end
