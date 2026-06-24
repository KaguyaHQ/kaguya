defmodule Kaguya.Auth.Google do
  @moduledoc """
  App-owned Google OAuth client for browser login.
  """

  @authorize_url "https://accounts.google.com/o/oauth2/v2/auth"
  @token_url "https://oauth2.googleapis.com/token"
  @userinfo_url "https://openidconnect.googleapis.com/v1/userinfo"
  @scopes ~w(openid email profile)

  def configured? do
    config = config()
    present?(config[:client_id]) and present?(config[:client_secret])
  end

  def generate_state do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  def generate_code_verifier do
    Kaguya.Auth.PKCE.generate_verifier()
  end

  def code_challenge(verifier) when is_binary(verifier) do
    Kaguya.Auth.PKCE.generate_challenge(verifier)
  end

  def authorize_url(state, redirect_uri, opts \\ [])
      when is_binary(state) and is_binary(redirect_uri) do
    with {:ok, config} <- fetch_config() do
      params = %{
        "response_type" => "code",
        "client_id" => Keyword.fetch!(config, :client_id),
        "redirect_uri" => redirect_uri,
        "scope" => Enum.join(@scopes, " "),
        "state" => state,
        "code_challenge" => Keyword.fetch!(opts, :code_challenge),
        "code_challenge_method" => "S256",
        "prompt" => "select_account"
      }

      {:ok, "#{@authorize_url}?#{URI.encode_query(params)}"}
    end
  end

  def fetch_profile(code, code_verifier, redirect_uri)
      when is_binary(code) and is_binary(code_verifier) and is_binary(redirect_uri) do
    with {:ok, access_token} <- exchange_code(code, code_verifier, redirect_uri) do
      userinfo(access_token)
    end
  end

  defp exchange_code(code, code_verifier, redirect_uri) do
    with {:ok, config} <- fetch_config() do
      form = [
        {"code", code},
        {"grant_type", "authorization_code"},
        {"client_id", Keyword.fetch!(config, :client_id)},
        {"client_secret", Keyword.fetch!(config, :client_secret)},
        {"redirect_uri", redirect_uri},
        {"code_verifier", code_verifier}
      ]

      opts =
        Keyword.merge(
          [form: form, headers: [{"accept", "application/json"}]],
          req_options()
        )

      case Req.post(@token_url, opts) do
        {:ok, %Req.Response{status: 200, body: %{"access_token" => token}}}
        when is_binary(token) ->
          {:ok, token}

        {:ok, %Req.Response{status: status, body: body}} ->
          {:error, {:google_token_exchange_failed, status, body}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp userinfo(access_token) do
    opts =
      Keyword.merge(
        [headers: [{"authorization", "Bearer #{access_token}"}, {"accept", "application/json"}]],
        req_options()
      )

    case Req.get(@userinfo_url, opts) do
      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) ->
        profile_from_userinfo(body)

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:google_userinfo_failed, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp profile_from_userinfo(%{"sub" => uid} = body) when is_binary(uid) do
    {:ok,
     %{
       provider: "google",
       provider_uid: uid,
       email: body["email"],
       email_verified: truthy?(body["email_verified"]),
       name: body["name"],
       avatar_url: body["picture"]
     }}
  end

  defp profile_from_userinfo(_body), do: {:error, :missing_google_subject}

  defp fetch_config do
    if configured?() do
      {:ok, config()}
    else
      {:error, :not_configured}
    end
  end

  defp config, do: Application.get_env(:kaguya, :google_oauth, [])
  defp req_options, do: Application.get_env(:kaguya, :google_req_options, [])

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
  defp truthy?(value), do: value in [true, "true", "1"]
end
