defmodule Kaguya.Auth.OAuthState do
  @moduledoc """
  Temporary storage for OAuth PKCE state payloads.
  Uses Cachex with 10-minute TTL. Keyed by the OAuth state parameter.

  The code_verifier is generated server-side when starting an OAuth flow,
  stored with callback metadata, and retrieved when the callback completes
  the exchange.
  Lost on machine restart — users mid-OAuth-flow will see a clear error
  and can retry.
  """

  @cache :kaguya_cache
  @ttl :timer.minutes(10)

  def generate_state do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  def store(state, payload) do
    Cachex.put(@cache, {:oauth_state, state}, payload, ttl: @ttl)
  end

  def retrieve_and_delete(state) do
    case Cachex.take(@cache, {:oauth_state, state}) do
      {:ok, nil} -> {:error, :state_not_found}
      {:ok, payload} -> {:ok, payload}
      {:error, _} -> {:error, :state_not_found}
    end
  end
end
