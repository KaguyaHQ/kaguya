defmodule Kaguya.Search do
  @moduledoc """
  Provides shared Meilisearch query logic.
  """

  alias Kaguya.Search.Client

  @doc """
  Generic function to query a Meilisearch index.
  """
  def search_index(index_name, query_string, page \\ 1, hits_per_page \\ 20, opts \\ []) do
    with {:ok, client} <- Client.new() do
      query_params =
        %{q: query_string, hitsPerPage: hits_per_page, page: page}
        |> maybe_add_filter(opts)

      case Req.post(client, url: "/indexes/#{index_name}/search", json: query_params) do
        {:ok, %{status: 200, body: body}} ->
          {:ok, body}

        {:ok, %{status: status}} ->
          {:error, "Search failed with status #{status}"}

        {:error, %{__exception__: true} = exception} ->
          {:error, "Search request failed: #{Exception.message(exception)}"}

        {:error, reason} ->
          {:error, "Search request failed: #{inspect(reason)}"}
      end
    end
  end

  @doc """
  Federated multi-index search — returns one merged list ranked by relevance.
  Each hit includes `_federation.indexUid` to identify the source index.
  Single HTTP call to Meilisearch /multi-search with federation enabled.

  Example:
      federated_search([
        %{indexUid: "visual_novels", q: "steins", limit: 5},
        %{indexUid: "characters", q: "steins", limit: 5},
        %{indexUid: "producers", q: "steins", limit: 5}
      ])
      # => {:ok, [%{"_federation" => %{"indexUid" => "visual_novels"}, "title" => "Steins;Gate", ...}, ...]}
  """
  def federated_search(queries, opts \\ []) when is_list(queries) do
    with {:ok, client} <- Client.new() do
      limit = Keyword.get(opts, :limit, 15)

      body = %{
        federation: %{limit: limit},
        queries: queries
      }

      case Req.post(client, url: "/multi-search", json: body) do
        {:ok, %{status: 200, body: %{"hits" => hits}}} ->
          # Federated response (Meilisearch v1.12+) — one merged list
          {:ok, hits}

        {:ok, %{status: 200, body: %{"results" => results}}} ->
          # Non-federated fallback (older Meilisearch) — flatten per-index results
          {:ok, flatten_results(results)}

        {:ok, %{status: status}} ->
          {:error, "Federated search failed with status #{status}"}

        {:error, reason} ->
          {:error, "Federated search failed: #{inspect(reason)}"}
      end
    end
  end

  defp flatten_results(results) do
    Enum.flat_map(results, fn %{"indexUid" => index_uid, "hits" => index_hits} ->
      Enum.map(index_hits, &Map.put(&1, "_federation", %{"indexUid" => index_uid}))
    end)
  end

  defp maybe_add_filter(params, opts) do
    case Keyword.get(opts, :filter) do
      nil -> params
      filter -> Map.put(params, :filter, filter)
    end
  end
end
