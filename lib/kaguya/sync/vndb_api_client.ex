defmodule Kaguya.Sync.VndbApiClient do
  @moduledoc """
  HTTP client for VNDB API v2 (api.vndb.org/kana).

  Handles pagination, rate limiting (200 req/5min, ~1 req/sec sustained),
  retries, and error handling. Uses Req with the global Finch pool.
  """

  require Logger

  @base_url "https://api.vndb.org/kana"
  @max_results 100
  @max_retries 3
  @bulk_chunk_size 50

  # ── VN Queries ─────────────────────────────────────────────────────────────

  @sweep_fields [
                  "id",
                  "title",
                  "aliases",
                  "titles.lang",
                  "titles.title",
                  "titles.latin",
                  "titles.official",
                  "titles.main",
                  "olang",
                  "devstatus",
                  "released",
                  "length",
                  "length_minutes",
                  "description",
                  "image.url",
                  "image.sexual",
                  "image.violence",
                  "image.votecount",
                  "rating",
                  "average",
                  "votecount"
                ]
                |> Enum.join(", ")

  @full_vn_fields [
                    "id",
                    "title",
                    "aliases",
                    "titles.lang",
                    "titles.title",
                    "titles.latin",
                    "titles.official",
                    "titles.main",
                    "olang",
                    "devstatus",
                    "released",
                    "length",
                    "length_minutes",
                    "description",
                    "image.url",
                    "image.sexual",
                    "image.violence",
                    "image.votecount",
                    "rating",
                    "average",
                    "votecount",
                    "tags.id",
                    "tags.rating",
                    "tags.spoiler",
                    "relations.id",
                    "relations.relation",
                    "relations.relation_official",
                    "developers.id",
                    "developers.name",
                    "developers.original",
                    "developers.description",
                    "developers.type",
                    "developers.lang",
                    "developers.extlinks.url",
                    "developers.extlinks.label",
                    "developers.extlinks.name"
                  ]
                  |> Enum.join(", ")

  @character_fields [
                      "id",
                      "name",
                      "original",
                      "aliases",
                      "description",
                      "image.url",
                      "image.sexual",
                      "image.violence",
                      "image.votecount",
                      "blood_type",
                      "height",
                      "weight",
                      "bust",
                      "waist",
                      "hips",
                      "cup",
                      "age",
                      "birthday",
                      "sex",
                      "gender",
                      "vns.id",
                      "vns.role",
                      "vns.spoiler"
                    ]
                    |> Enum.join(", ")

  @release_fields [
                    "id",
                    "title",
                    "titles.lang",
                    "titles.title",
                    "titles.latin",
                    "titles.mtl",
                    "olang",
                    "released",
                    "patch",
                    "freeware",
                    "official",
                    "has_ero",
                    "uncensored",
                    "voiced",
                    "minage",
                    "engine",
                    "notes",
                    "reso_x",
                    "reso_y",
                    "media.medium",
                    "media.qty",
                    "platforms",
                    "languages",
                    "extlinks.url",
                    "extlinks.label",
                    "extlinks.name",
                    "vns.id",
                    "vns.rtype",
                    "producers.id",
                    "producers.developer",
                    "producers.publisher",
                    "producers.name"
                  ]
                  |> Enum.join(", ")

  @tag_fields [
                "id",
                "name",
                "description",
                "category"
              ]
              |> Enum.join(", ")

  @doc """
  Stream all VNs with lightweight sweep fields.
  Returns a stream of pages (each page is a list of VN maps).

  Options:
    - `:from` — start from this vndb_id (e.g. "v50000"), uses `>=` for first page

  Uses cursor-based pagination via `["id", ">", last_id]` for efficiency.
  On API error, emits a final `{:error, reason}` element so the caller
  can distinguish a complete sweep from a partial one.
  """
  def stream_all_vns(opts \\ []) do
    start_from = Keyword.get(opts, :from)

    Stream.resource(
      fn -> {:first_page, start_from} end,
      fn
        :halt ->
          {:halt, :done}

        {:first_page, nil} ->
          fetch_sweep_page(">=", "v1")

        {:first_page, cursor} ->
          fetch_sweep_page(">=", cursor)

        cursor when is_binary(cursor) ->
          fetch_sweep_page(">", cursor)
      end,
      fn _ -> :ok end
    )
  end

  defp fetch_sweep_page(op, id) do
    case post("/vn", %{
           filters: ["id", op, id],
           fields: @sweep_fields,
           sort: "id",
           results: @max_results
         }) do
      {:ok, %{"results" => results, "more" => more}} when results != [] ->
        last = List.last(results)["id"]
        if more, do: {[results], last}, else: {[results], :halt}

      {:ok, _} ->
        {:halt, :done}

      {:error, reason} ->
        Logger.error("VNDB API sweep failed at cursor #{inspect(id)}: #{inspect(reason)}")
        {[{:error, reason}], :halt}
    end
  end

  @doc """
  Fetch a single VN with full fields (including tags, relations, developers).
  """
  def get_vn(vndb_id, opts \\ []) do
    case post(
           "/vn",
           %{
             filters: ["id", "=", vndb_id],
             fields: @full_vn_fields,
             results: 1
           },
           opts
         ) do
      {:ok, %{"results" => [vn]}} -> {:ok, vn}
      {:ok, %{"results" => []}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Fetch all characters linked to a VN.
  Returns a flat list of character maps.
  """
  def list_characters_for_vn(vndb_id, opts \\ []) do
    paginate_all("/character", ["vn", "=", ["id", "=", vndb_id]], @character_fields, opts)
  end

  @doc """
  Fetch all releases for a VN. Used to derive has_ero and min_age.
  """
  def list_releases_for_vn(vndb_id, opts \\ []) do
    paginate_all("/release", ["vn", "=", ["id", "=", vndb_id]], @release_fields, opts)
  end

  @doc """
  Fetch releases for multiple VNs at once.
  Chunks IDs to avoid exceeding API filter limits.
  Returns a flat list of release maps with their VN associations.
  """
  def list_releases_for_vns(vndb_ids, opts \\ []) when is_list(vndb_ids) do
    chunked_fetch(vndb_ids, fn ids ->
      filters = build_or_filter("vn", ids)
      paginate_all("/release", filters, @release_fields, opts)
    end)
  end

  @doc """
  Fetch tags by their VNDB IDs (e.g. ["g339", "g608"]).
  Chunks IDs to avoid exceeding API filter limits.
  Returns {:ok, [tag_map]} or {:error, reason}.
  """
  def get_tags_by_ids(tag_ids, opts \\ []) when is_list(tag_ids) do
    tag_ids
    |> Enum.chunk_every(@bulk_chunk_size)
    |> Enum.reduce_while([], fn chunk, acc ->
      filters = build_simple_or_filter(chunk)

      case post("/tag", %{filters: filters, fields: @tag_fields, results: @max_results}, opts) do
        {:ok, %{"results" => results}} -> {:cont, results ++ acc}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:error, reason} -> {:error, reason}
      results -> {:ok, results}
    end
  end

  @doc """
  Fetch multiple VNs by ID with full fields.
  Batches into groups of up to 100 IDs per request.
  Returns {:ok, [vn_map]} or {:error, reason}.
  """
  def get_vns_by_ids(vndb_ids) when is_list(vndb_ids) do
    vndb_ids
    |> Enum.chunk_every(@max_results)
    |> Enum.reduce_while([], fn chunk, acc ->
      filters = build_simple_or_filter(chunk)

      case post("/vn", %{filters: filters, fields: @full_vn_fields, results: @max_results}) do
        {:ok, %{"results" => results}} -> {:cont, results ++ acc}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:error, reason} -> {:error, reason}
      results -> {:ok, results}
    end
  end

  @doc """
  Fetch characters for multiple VNs at once.
  Chunks IDs to avoid exceeding API filter limits.
  Returns a flat list of character maps with their VN associations.
  """
  def list_characters_for_vns(vndb_ids, opts \\ []) when is_list(vndb_ids) do
    chunked_fetch(vndb_ids, fn ids ->
      filters = build_or_filter("vn", ids)
      paginate_all("/character", filters, @character_fields, opts)
    end)
  end

  # ── Internal ───────────────────────────────────────────────────────────────

  defp paginate_all(endpoint, filters, fields, opts) do
    do_paginate(endpoint, filters, fields, 1, [], opts)
  end

  defp do_paginate(endpoint, filters, fields, page, acc, opts) do
    case post(
           endpoint,
           %{
             filters: filters,
             fields: fields,
             results: @max_results,
             page: page
           },
           opts
         ) do
      {:ok, %{"results" => results, "more" => true}} ->
        do_paginate(endpoint, filters, fields, page + 1, [results | acc], opts)

      {:ok, %{"results" => results}} ->
        {:ok, acc |> Enum.reverse() |> List.flatten() |> Kernel.++(results)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Chunk vndb_ids and fetch with a function, combining results
  defp chunked_fetch(vndb_ids, fetch_fn) do
    vndb_ids
    |> Enum.chunk_every(@bulk_chunk_size)
    |> Enum.reduce_while([], fn chunk, acc ->
      case fetch_fn.(chunk) do
        {:ok, results} -> {:cont, results ++ acc}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:error, reason} -> {:error, reason}
      results -> {:ok, results}
    end
  end

  # Build ["or", ["vn", "=", ["id", "=", "v1"]], ...] filter for nested VN lookups
  defp build_or_filter(field, ids) do
    case ids do
      [single] -> [field, "=", ["id", "=", single]]
      multiple -> ["or" | Enum.map(multiple, &[field, "=", ["id", "=", &1]])]
    end
  end

  # Build ["or", ["id", "=", "v1"], ...] filter for direct ID lookups
  defp build_simple_or_filter(ids) do
    case ids do
      [single] -> ["id", "=", single]
      multiple -> ["or" | Enum.map(multiple, &["id", "=", &1])]
    end
  end

  defp post(endpoint, body, opts \\ []) do
    do_post(endpoint, body, 0, Keyword.get(opts, :throttle, true))
  end

  defp do_post(endpoint, body, retries, throttle?) do
    if throttle?, do: Kaguya.Sync.VndbRateLimiter.throttle()

    case Req.post("#{@base_url}#{endpoint}",
           json: body,
           receive_timeout: 30_000,
           pool_timeout: 10_000
         ) do
      {:ok, %Req.Response{status: 200, body: resp_body}} ->
        {:ok, resp_body}

      {:ok, %Req.Response{status: 429}} ->
        if retries < @max_retries do
          wait = :timer.seconds(5) * (retries + 1)

          Logger.warning(
            "VNDB API rate limited, waiting #{div(wait, 1000)}s (retry #{retries + 1})"
          )

          Process.sleep(wait)
          do_post(endpoint, body, retries + 1, throttle?)
        else
          {:error, :rate_limited}
        end

      {:ok, %Req.Response{status: status, body: resp_body}} ->
        if retries < @max_retries and status >= 500 do
          Process.sleep(:timer.seconds(2))
          do_post(endpoint, body, retries + 1, throttle?)
        else
          Logger.error("VNDB API error #{status}: #{inspect(resp_body)}")
          {:error, {:api_error, status, resp_body}}
        end

      {:error, reason} ->
        if retries < @max_retries do
          Process.sleep(:timer.seconds(2))
          do_post(endpoint, body, retries + 1, throttle?)
        else
          {:error, reason}
        end
    end
  end
end
