defmodule Kaguya.Cdn do
  @moduledoc """
  Cloudflare CDN cache management.

  Purges edge-cached pages when underlying data changes so refreshes always
  serve fresh content.
  """

  require Logger

  @site_url "https://kaguya.io"
  @max_urls_per_request 30

  @doc """
  VN detail pages are currently LiveView-rendered with private cache headers.
  Cloudflare does not store `/vn/:slug` HTML, so purging it is intentionally a
  no-op until public VN edge caching is restored.
  """
  def purge_vn_cache(vn_slug) when is_binary(vn_slug), do: :ok

  def purge_character_cache(character_slug) when is_binary(character_slug) do
    purge_urls([character_page_url(character_slug)])
  end

  def purge_producer_cache(producer_slug) when is_binary(producer_slug) do
    purge_urls([producer_page_url(producer_slug)])
  end

  @doc """
  Purge the edge-cached single-review page for `username`'s review of
  `vn_slug`. Mirrors `purge_vn_cache/1` for review mutations.
  """
  def purge_review_page(username, vn_slug)
      when is_binary(username) and is_binary(vn_slug) do
    purge_urls([review_page_url(username, vn_slug)])
  end

  def purge_review_page(_username, _vn_slug), do: :ok

  @doc """
  Purge the global `/site-stats` page. Called by the daily site-stats
  worker (after the snapshot lands) and by the backfill task. Async, no-op
  on missing CF credentials — same contract as the other helpers above.
  """
  def purge_site_stats, do: purge_urls([site_stats_url()])

  @doc """
  Bulk-purge pages for multiple entities at once (single Task, batched requests).
  Accepts keyword list with `:vn_slugs`, `:character_slugs`, `:producer_slugs`.
  `:vn_slugs` is currently ignored because VN LiveView HTML is not edge-cached.
  """
  def purge_pages(opts) when is_list(opts) do
    urls =
      Enum.map(Keyword.get(opts, :character_slugs, []), &character_page_url/1) ++
        Enum.map(Keyword.get(opts, :producer_slugs, []), &producer_page_url/1)

    if urls != [], do: purge_urls(urls)
  end

  @doc """
  Purge Cloudflare's edge cache for the given URLs.
  Batches into chunks of #{@max_urls_per_request} (Cloudflare API limit).
  """
  def purge_urls(urls) when is_list(urls) and urls != [] do
    zone_id = System.get_env("CF_ZONE_ID")
    api_token = System.get_env("CF_API_TOKEN")

    if zone_id && api_token do
      Task.start(fn ->
        urls
        |> Enum.chunk_every(@max_urls_per_request)
        |> Enum.each(fn chunk ->
          try do
            resp =
              Req.post!(
                "https://api.cloudflare.com/client/v4/zones/#{zone_id}/purge_cache",
                json: %{files: chunk},
                headers: [
                  {"Authorization", "Bearer #{api_token}"},
                  {"Content-Type", "application/json"}
                ]
              )

            if resp.status == 200 do
              Logger.info("[Cdn] Purged #{length(chunk)} URL(s)")
            else
              Logger.warning("[Cdn] Purge failed (#{resp.status}): #{inspect(resp.body)}")
            end
          rescue
            e ->
              Logger.warning("[Cdn] Purge request failed: #{Exception.message(e)}")
          end
        end)
      end)
    end
  end

  def purge_urls([]), do: :ok

  defp character_page_url(slug), do: "#{@site_url}/characters/#{slug}"
  defp producer_page_url(slug), do: "#{@site_url}/producers/#{slug}"
  defp site_stats_url, do: "#{@site_url}/site-stats"
  # Canonical URL: `/@username/reviews/slug`. `/users/...` permanently
  # redirects here, so Cloudflare caches the rendered page under this path.
  defp review_page_url(username, slug), do: "#{@site_url}/@#{username}/reviews/#{slug}"
end
