defmodule KaguyaWeb.BrowserAuthController do
  use KaguyaWeb, :controller

  alias Kaguya.Auth
  alias Kaguya.Auth.{Google, OAuthState}
  alias Kaguya.Users
  alias KaguyaWeb.UserAuth

  require Logger

  @signup_email_key "signup_email"
  @signup_return_to_key "signup_return_to"
  @magic_link_message "If that email can receive Kaguya links, we'll send a sign-in link shortly."

  def sign_in(conn, %{"email" => email} = params) do
    return_to = safe_return_to(params["return_to"] || params["redirectTo"])

    conn
    |> request_magic_link(email, return_to)
    |> put_flash(:info, @magic_link_message)
    |> redirect(to: login_email_sent_path(email, return_to))
  end

  def sign_up(conn, %{"email" => email} = params) do
    return_to = safe_return_to(params["return_to"] || params["redirectTo"])

    conn
    |> request_magic_link(email, return_to)
    |> put_session(@signup_email_key, email)
    |> put_session(@signup_return_to_key, return_to)
    |> put_flash(:info, @magic_link_message)
    |> redirect(to: ~p"/signup?action=confirm_email")
  end

  def verify_email(conn, %{"email" => email} = params) do
    return_to = safe_return_to(params["return_to"] || get_session(conn, @signup_return_to_key))

    conn
    |> request_magic_link(email, return_to)
    |> put_session(@signup_email_key, email)
    |> put_session(@signup_return_to_key, return_to)
    |> put_flash(:info, @magic_link_message)
    |> redirect(to: ~p"/signup?action=confirm_email")
  end

  def resend_confirmation(conn, %{"email" => email} = params) do
    verify_email(conn, Map.put(params, "email", email))
  end

  def reset_password(conn, %{"email" => email}) do
    conn
    |> request_magic_link(email, "/")
    |> put_flash(:info, @magic_link_message)
    |> redirect(to: ~p"/login?reset_password=true&action=email_sent")
  end

  def update_recovery_password(conn, _params) do
    conn
    |> put_flash(:info, "Password login is no longer used. Please sign in with your email link.")
    |> redirect(to: ~p"/login")
  end

  def update_password(conn, _params) do
    conn
    |> put_flash(:info, "Password login is no longer used. Please sign in with your email link.")
    |> redirect(to: ~p"/account/settings")
  end

  def update_email(conn, %{"email" => email}) do
    with %{id: user_id} <- conn.assigns[:current_user],
         {:ok, user} <- Users.get_user(user_id),
         :ok <- validate_new_email(user.email, email),
         {:ok, _email} <-
           Auth.deliver_update_email_instructions(
             user,
             email,
             fn token ->
               request_origin(conn) <> ~p"/auth/confirm?type=email_change&token=#{token}"
             end
           ) do
      conn
      |> put_flash(:info, "Email verification link sent")
      |> redirect(to: ~p"/account/edit/email")
    else
      {:error, :same_email} ->
        conn
        |> put_flash(:auth_error, "Please enter a different email.")
        |> redirect(to: ~p"/account/edit/email")

      {:error, %Ecto.Changeset{}} ->
        conn
        |> put_flash(:auth_error, "This email is taken or invalid. Please try another.")
        |> redirect(to: ~p"/account/edit/email")

      _ ->
        conn
        |> put_flash(:auth_error, "Something went wrong. Please try again.")
        |> redirect(to: ~p"/account/edit/email")
    end
  end

  def update_email_legacy_redirect(conn, params) do
    query = if params == %{}, do: "", else: "?" <> URI.encode_query(params)
    redirect(conn, to: "/auth/confirm" <> query)
  end

  def sign_out(conn, params) do
    return_to = safe_return_to(params["return_to"])

    conn
    |> UserAuth.log_out_user()
    |> put_flash(:info, "Signed out")
    |> redirect(to: return_to)
  end

  def start_google(conn, params) do
    return_to = safe_return_to(params["return_to"])

    with :ok <- rate_limit_auth(conn, "google_oauth", 20),
         true <- Google.configured?(),
         state <- OAuthState.generate_state(),
         verifier <- Google.generate_code_verifier(),
         redirect_uri <- google_redirect_uri(conn),
         challenge <- Google.code_challenge(verifier),
         {:ok, true} <-
           OAuthState.store(state, %{
             verifier: verifier,
             return_to: return_to,
             redirect_uri: redirect_uri
           }),
         {:ok, url} <- Google.authorize_url(state, redirect_uri, code_challenge: challenge) do
      redirect(conn, external: url)
    else
      false ->
        conn
        |> put_flash(:error, "Google sign-in is not configured yet. Use email sign-in.")
        |> redirect(to: return_to)

      reason ->
        Logger.warning("google oauth start failed: #{inspect(reason)}")

        conn
        |> put_flash(:error, "Google sign-in is unavailable. Use email sign-in.")
        |> redirect(to: return_to)
    end
  end

  def callback(conn, %{"error" => _error, "state" => state}) do
    return_to =
      case OAuthState.retrieve_and_delete(state) do
        {:ok, %{return_to: return_to}} -> return_to
        _ -> "/"
      end

    conn
    |> put_flash(:error, "Google sign-in was cancelled.")
    |> redirect(to: return_to)
  end

  def callback(conn, %{"error" => _error} = params) do
    return_to = safe_return_to(params["return_to"])

    conn
    |> put_flash(:error, "Google sign-in was cancelled.")
    |> redirect(to: return_to)
  end

  def callback(conn, %{"code" => code, "state" => state}) do
    with {:ok, %{verifier: verifier, return_to: return_to, redirect_uri: redirect_uri}} <-
           OAuthState.retrieve_and_delete(state),
         {:ok, profile} <- Google.fetch_profile(code, verifier, redirect_uri),
         {:ok, user} <- Auth.login_user_by_google_profile(profile) do
      redirect_to = if Auth.needs_setup?(user), do: setup_path(return_to), else: return_to

      conn
      |> UserAuth.log_in_user(user)
      |> put_flash(:info, "Signed in")
      |> redirect(to: redirect_to)
    else
      {:error, :state_not_found} ->
        conn
        |> put_flash(:error, "This Google sign-in link expired. Please try again.")
        |> redirect(to: ~p"/login")

      {:error, :email_not_verified} ->
        conn
        |> put_flash(:error, "Google did not verify that email address. Use email sign-in.")
        |> redirect(to: ~p"/login")

      {:error, :provider_already_linked} ->
        conn
        |> put_flash(:error, "That Google account is already linked to another user.")
        |> redirect(to: ~p"/login")

      reason ->
        Logger.warning("google oauth callback failed: #{inspect(reason)}")

        conn
        |> put_flash(:error, "Google sign-in failed. Use email sign-in.")
        |> redirect(to: ~p"/login")
    end
  end

  def callback(conn, _params) do
    conn
    |> put_flash(:error, "Google sign-in failed. Use email sign-in.")
    |> redirect(to: ~p"/login")
  end

  def confirm(conn, %{"type" => "email_change", "token" => token}) do
    case Auth.update_user_email_by_token(token) do
      {:ok, user} ->
        conn
        |> UserAuth.log_in_user(user)
        |> put_flash(:info, "Email updated")
        |> redirect(to: ~p"/account/edit/email")

      _ ->
        conn
        |> put_flash(:error, "This email verification link is invalid or expired.")
        |> redirect(to: ~p"/account/edit/email")
    end
  end

  def confirm(conn, %{"token" => token} = params) do
    return_to = safe_return_to(params["return_to"] || get_session(conn, @signup_return_to_key))

    case Auth.login_user_by_magic_link(token) do
      {:ok, user} ->
        redirect_to = if Auth.needs_setup?(user), do: setup_path(return_to), else: return_to

        conn
        |> delete_session(@signup_email_key)
        |> delete_session(@signup_return_to_key)
        |> UserAuth.log_in_user(user)
        |> put_flash(:info, "Signed in")
        |> redirect(to: redirect_to)

      _ ->
        conn
        |> put_flash(:error, "This sign-in link is invalid or expired.")
        |> redirect(to: ~p"/login")
    end
  end

  def confirm(conn, _params), do: redirect(conn, to: ~p"/login")

  defp request_magic_link(conn, email, return_to) do
    with :ok <- rate_limit_auth(conn, "magic_link", 8),
         {:ok, user} <- Auth.ensure_user_by_email(email),
         {:ok, _email} <-
           Auth.deliver_login_instructions(
             user,
             fn token ->
               request_origin(conn) <> ~p"/auth/confirm?token=#{token}&return_to=#{return_to}"
             end
           ) do
      conn
    else
      reason ->
        Logger.warning("magic link request failed: #{inspect(reason)}")
        conn
    end
  end

  defp validate_new_email(current_email, new_email) when is_binary(new_email) do
    if String.downcase(current_email || "") == String.downcase(String.trim(new_email)) do
      {:error, :same_email}
    else
      :ok
    end
  end

  defp validate_new_email(_current_email, _new_email), do: {:error, :invalid_email}

  defp rate_limit_auth(conn, operation, limit) do
    bucket = "auth:#{operation}:#{client_ip(conn)}"

    case Kaguya.RateLimit.hit(bucket, :timer.minutes(15), limit) do
      {:allow, _} -> :ok
      {:deny, _} -> {:error, :rate_limited}
    end
  end

  defp client_ip(conn) do
    conn.remote_ip
    |> Tuple.to_list()
    |> Enum.join(".")
  end

  defp safe_return_to(path) when is_binary(path) do
    if String.starts_with?(path, "/") and not String.starts_with?(path, "//"), do: path, else: "/"
  end

  defp safe_return_to(_), do: "/"

  defp setup_path("/"), do: ~p"/signup?action=account_setup"
  defp setup_path(return_to), do: ~p"/signup?action=account_setup&return_to=#{return_to}"

  defp request_origin(conn) do
    scheme = Atom.to_string(conn.scheme)

    port =
      case {conn.scheme, conn.port} do
        {:http, 80} -> ""
        {:https, 443} -> ""
        {_scheme, port} -> ":#{port}"
      end

    "#{scheme}://#{conn.host}#{port}"
  end

  defp google_redirect_uri(conn) do
    config = Application.get_env(:kaguya, :google_oauth, [])

    case config[:redirect_uri] do
      uri when is_binary(uri) and uri != "" -> uri
      _ -> request_origin(conn) <> ~p"/auth/callback"
    end
  end

  defp login_email_sent_path(_email, "/"), do: ~p"/login?action=email_sent"

  defp login_email_sent_path(email, return_to),
    do: ~p"/login?action=email_sent&email=#{email}&return_to=#{return_to}"
end
