defmodule Kaguya.VisualNovels.VNPageCache do
  @moduledoc """
  Origin-side cache for the viewer-independent core of the VN detail page
  (`/vn/:slug` → `KaguyaWeb.VNLive.Show`).

  This is the replacement for the Cloudflare edge cache the legacy Next.js
  page relied on (`Cache-Control: s-maxage=…`), which a LiveView page can't
  carry (CSRF token + session + websocket upgrade). The assembled core is
  cached per VN × content-pref combo × mod visibility; per-user state (vote
  highlights, private lists) is *not* part of it — see
  `KaguyaWeb.VNLive.PageData.build_public_page/4`.

  The cache key is opaque to this module beyond two facts: it's a tuple, and
  its second element is the VN id. That's all `invalidate/1` needs, so the
  page-shape dimensions (page, sort, prefs) stay owned by the web layer.

  Invalidation mirrors the `BrowseSections.refresh/0` convention: write paths
  that change a single VN's public core (reviews, ratings, tag votes,
  similarity votes, merges, renames, deletions, sync) call `invalidate/1`.
  """

  @cache :vn_page_cache

  @doc "The Cachex instance name, for callers that need a full `clear/0`."
  def cache, do: @cache

  @doc """
  Fetch-or-compute the cached core for `key`. `fun` is a 0-arity function
  returning the payload to commit on a miss. Mirrors
  `Kaguya.VisualNovels.Browse.list/1`'s `Cachex.fetch` shape, falling back to
  a direct compute if Cachex errors so a cache hiccup never blanks the page.
  """
  def fetch(key, fun) when is_function(fun, 0) do
    case Cachex.fetch(@cache, key, fn -> {:commit, fun.()} end) do
      {:ok, payload} -> payload
      {:commit, payload} -> payload
      _ -> fun.()
    end
  end

  @doc """
  Drops every cached variant (page/sort/pref/visibility) for one VN. Streams
  the keyspace and deletes the matching `{:vn_page, vn_id, …}` entries — exact,
  so it never over-clears sibling VNs the way `Cachex.clear/1` would.
  """
  def invalidate(vn_id) do
    query = Cachex.Query.build(output: :key)

    @cache
    |> Cachex.stream!(query)
    |> Enum.each(fn key ->
      if match_vn?(key, vn_id), do: Cachex.del(@cache, key)
    end)

    :ok
  rescue
    # A cache that isn't running (e.g. a context unit test that doesn't boot
    # the app supervisor) must not crash a write. The next read just recomputes.
    _ -> :ok
  end

  @doc """
  Drops every cached VN-page entry. For broad mutations where a per-VN sweep
  isn't worth it — a VNDB sync, a merge/rename/deletion, or a user-wide rating
  recalc that touches an unbounded set of VNs. Mirrors the
  `Cachex.clear(:vn_browse_cache)` calls at those same sites.
  """
  def clear_all do
    Cachex.clear(@cache)
    :ok
  rescue
    _ -> :ok
  end

  defp match_vn?(key, vn_id) when is_tuple(key) and tuple_size(key) >= 2 do
    elem(key, 0) == :vn_page and elem(key, 1) == vn_id
  end

  defp match_vn?(_key, _vn_id), do: false
end
