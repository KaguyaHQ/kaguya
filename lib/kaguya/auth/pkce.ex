defmodule Kaguya.Auth.PKCE do
  @moduledoc """
  Shared PKCE helpers for app-owned OAuth flows.
  """

  def generate_verifier do
    :crypto.strong_rand_bytes(64) |> Base.url_encode64(padding: false)
  end

  def generate_challenge(verifier) when is_binary(verifier) do
    :crypto.hash(:sha256, verifier) |> Base.url_encode64(padding: false)
  end
end
