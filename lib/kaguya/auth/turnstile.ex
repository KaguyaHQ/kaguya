defmodule Kaguya.Auth.Turnstile do
  @moduledoc "Server-side verification for every browser request for a login email."

  @verify_url "https://challenges.cloudflare.com/turnstile/v0/siteverify"
  @action "email_login"
  @test_secret_keys [
    "1x0000000000000000000000000000000AA",
    "2x0000000000000000000000000000000AA",
    "3x0000000000000000000000000000000AA"
  ]

  def action, do: @action
  def site_key, do: config()[:site_key] || ""

  def verify(token, ip) do
    started = System.monotonic_time()
    result = verify_token(token, ip)

    :telemetry.execute(
      [:kaguya, :auth, :turnstile, :stop],
      %{duration: System.monotonic_time() - started, count: 1},
      %{result: if(result == :ok, do: :verified, else: :rejected), reason: reason(result)}
    )

    result
  end

  defp verify_token(token, ip) when is_binary(token) and byte_size(token) in 1..2048 do
    settings = config()

    if configured?(settings) do
      opts =
        Keyword.merge(
          [
            form: [secret: settings[:secret_key], response: token, remoteip: ip],
            receive_timeout: 5_000,
            # Override the app-wide Finch default to use a pool with a bounded
            # connect timeout. Req disallows connect_options with a named pool.
            finch: nil,
            connect_options: [timeout: 5_000],
            retry: false,
            redirect: false
          ],
          Application.get_env(:kaguya, :turnstile_req_options, [])
        )

      case Req.post(@verify_url, opts) do
        {:ok, %Req.Response{status: 200, body: body}} when is_map(body) ->
          validate_response(body, settings)

        _ ->
          {:error, :verification_unavailable}
      end
    else
      {:error, :not_configured}
    end
  end

  defp verify_token(_, _), do: {:error, :missing_or_invalid_token}

  defp validate_response(body, settings) do
    cond do
      body["success"] != true -> {:error, :invalid_or_expired_token}
      test_response?(body, settings) -> :ok
      body["hostname"] not in settings[:hostnames] -> {:error, :hostname_mismatch}
      body["action"] != @action -> {:error, :action_mismatch}
      true -> :ok
    end
  end

  # Cloudflare's dummy keys return example.com without echoing the action.
  # Accept that response only with an official test secret outside production.
  defp test_response?(body, settings) do
    settings[:allow_test_keys] == true and settings[:secret_key] in @test_secret_keys and
      body["hostname"] == "example.com" and is_nil(body["action"])
  end

  defp configured?(settings) do
    present?(settings[:site_key]) and present?(settings[:secret_key]) and
      is_list(settings[:hostnames]) and settings[:hostnames] != [] and
      (settings[:allow_test_keys] == true or
         not String.starts_with?(settings[:secret_key], ["1x", "2x", "3x"]))
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
  defp config, do: Application.get_env(:kaguya, :turnstile, [])
  defp reason(:ok), do: :verified
  defp reason({:error, reason}), do: reason
end
