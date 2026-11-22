defmodule Kaguya.Search.Client do
  @moduledoc false

  def new do
    config = Application.fetch_env!(:kaguya, :meilisearch)

    if is_binary(config[:base_url]) and String.trim(config[:base_url]) != "" do
      {:ok,
       Req.new(
         base_url: String.trim(config[:base_url]),
         auth: {:bearer, config[:master_key] || ""},
         receive_timeout: 5_000,
         retry: false,
         redirect: false
       )
       |> Req.merge(Map.get(config, :req_options, []))}
    else
      {:error, :not_configured}
    end
  end

  def healthy? do
    with {:ok, client} <- new(),
         {:ok, %{status: 200, body: %{"status" => "available"}}} <-
           Req.get(client,
             url: "/health",
             receive_timeout: 1_000,
             pool_timeout: 1_000
           ) do
      true
    else
      _ -> false
    end
  end
end
