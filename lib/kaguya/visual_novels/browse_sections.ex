defmodule Kaguya.VisualNovels.BrowseSections do
  @moduledoc """
  Static configuration for the /browse explore-mode carousel rows.

  Each section is a `(filters, sort_by)` pair that maps directly onto the
  existing `list_visual_novels` resolver — no bespoke resolver needed.
  Cache keys auto-segregate per section because filters are part of the
  `:vn_browse_cache` key hash.

  The filter shape is the contract for these sections.
  """

  require Logger

  @type section :: %{
          id: atom(),
          sort_by: atom() | nil,
          filters: map()
        }

  @sections [
    %{
      id: :popular,
      sort_by: :total_ratings_desc,
      # Sorting by total_ratings DESC already surfaces the most-rated VNs;
      # a `ratings_count_gte` floor on top of that is redundant for the top
      # of the list. Kept empty so the carousel and the "see all" grid
      # produce identical first-page results.
      filters: %{}
    },
    %{
      id: :avn,
      sort_by: :total_ratings_desc,
      # `is_avn` is a curated boolean column on `visual_novels` (backed by
      # the partial `visual_novels_is_avn_index WHERE is_avn = true`). It
      # captures the AVN-scene cluster — Eternum, Being a DIK, etc. —
      # cleanly: neither `en + has_ero` nor `Ren'Py + has_ero` separates
      # AVNs from classical Western VNs (both clusters share engine and
      # language), and the older `western` tag bucket included non-AVN
      # Western releases like Katawa Shoujo and the Sakura series.
      filters: %{is_avn: true, ratings_count_gte: 1}
    },
    %{
      id: :romance,
      # nil → resolver auto-picks :relevance_desc when tags are present
      sort_by: nil,
      filters: %{include_tags: ["romance"]}
    },
    %{
      id: :otome,
      # nil → resolver auto-picks :relevance_desc when tags are present
      sort_by: nil,
      filters: %{include_tags: ["otome-game"]}
    },
    %{
      id: :free_on_itch,
      sort_by: :total_ratings_desc,
      # Compound predicate: release.freeware AND extlink.site = "itch" on the
      # SAME release. ~91% of itch-extlinked VNs qualify — itch is mostly free
      # — and using the stricter filter keeps paid commercial Ren'Py releases
      # sold on itch out of the discovery shelf, matching the row's title.
      filters: %{free_on_stores: ["itch"], ratings_count_gte: 1}
    }
  ]

  # Default page-1 size for each section. Matches what the carousel asks for
  # on first paint, so the warmed cache is hit by the very first request.
  # Kept in lockstep with the LiveView explore row size.
  @warm_page_size 36

  # The content-pref combinations the frontend can ask for. The cache key
  # hash includes `include_nukige`/`include_adjacent`, so each combo lives
  # in its own Cachex slot and we warm all four to cover the full matrix.
  # Without this, a logged-in user with nukige enabled would always hit a
  # cold cache on first request because the default warm uses (off, off).
  @prefs_matrix [
    %{include_nukige: false, include_adjacent: false},
    %{include_nukige: true, include_adjacent: false},
    %{include_nukige: false, include_adjacent: true},
    %{include_nukige: true, include_adjacent: true}
  ]

  def all, do: @sections

  @doc """
  Look up a section by id. Returns nil if not found. Used by callers that
  want to construct a "see all" link or share a single section's filter
  shape with the frontend.
  """
  def get(id), do: Enum.find(@sections, &(&1.id == id))

  @doc """
  Synchronously warm the page-1 cache entry for every configured section,
  across all 4 content-pref combinations. Returns `{:ok, count}` with the
  number of (section × prefs) pairs successfully primed.

  A single section's failure (e.g., a DB blip) is caught and logged so the
  remaining sections still get warmed. Idempotent — `Cachex.fetch` is a
  no-op when the key is already present.
  """
  def warm_sync(opts \\ []) do
    page_size = Keyword.get(opts, :page_size, @warm_page_size)

    count =
      for section <- @sections, prefs <- @prefs_matrix, reduce: 0 do
        acc ->
          merged_section = %{section | filters: Map.merge(section.filters, prefs)}

          try do
            :ok = warm_section(merged_section, page_size)
            acc + 1
          rescue
            e ->
              Logger.warning(
                "[BrowseSections] failed to warm #{section.id} #{inspect(prefs)}: " <>
                  Exception.message(e)
              )

              acc
          end
      end

    {:ok, count}
  end

  @doc """
  Fire-and-forget warm. Spawns an unlinked Task; never crashes the caller.
  Use this from hooks that run after `Cachex.clear/1` so users hit a warm
  cache on the next request.
  """
  def warm_async(opts \\ []) do
    if Application.get_env(:kaguya, :browse_cache_warm_async, true) do
      do_warm_async(opts)
    end

    :ok
  end

  defp do_warm_async(opts) do
    Task.start(fn ->
      try do
        warm_sync(opts)
      rescue
        e ->
          Logger.warning("[BrowseSections] async warm raised: #{Exception.message(e)}")
      end
    end)
  end

  @doc """
  Clear the browse cache and asynchronously re-warm the explore-mode
  sections. Replaces inline `Cachex.clear(:vn_browse_cache)` calls at sites
  where the explore page should never serve a cold first request.

  Also drops the VN-page core cache: every site that broadly refreshes browse
  data (merge, rename, deletion, VNDB sync) has, by definition, changed VN
  content that the per-VN page core also caches.
  """
  def refresh do
    Cachex.clear(:vn_browse_cache)
    Kaguya.VisualNovels.VNPageCache.clear_all()
    warm_async()
  end

  defp warm_section(%{filters: filters, sort_by: sort_by}, page_size) do
    _ =
      Kaguya.VisualNovels.browse_visual_novels(
        filters: filters,
        page: 1,
        page_size: page_size,
        sort_by: sort_by
      )

    :ok
  end
end
