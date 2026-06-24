defmodule Kaguya.Producers do
  @moduledoc """
  The Producers context.
  """

  @behaviour Kaguya.Revisions.EntityContext

  import Ecto.Query
  alias Kaguya.Repo

  alias Kaguya.Producers.{Producer, ProducerExternalLink, VNProducer}
  alias Kaguya.VisualNovels.VisualNovel
  alias Kaguya.SearchIndex

  def can_edit_producer?(%Producer{is_locked: true}, %{role: :admin}), do: true
  def can_edit_producer?(%Producer{is_locked: true}, %{mod_db: true}), do: true
  def can_edit_producer?(%Producer{is_locked: true}, _user), do: false

  def can_edit_producer?(%Producer{}, %{role: :admin}), do: true
  def can_edit_producer?(%Producer{}, %{mod_db: true}), do: true

  def can_edit_producer?(%Producer{}, %{id: _} = user),
    do: Map.get(user, :can_edit, true) != false

  def can_edit_producer?(_, _), do: false

  @doc """
  Selects the "primary" producers for a VN from a list of vn_producer rows.

  This mirrors the developer-only selection logic used by the VN page and
  the Meilisearch index, so callers (e.g. `Kaguya.Stats`)
  see the same producer set users actually see in the rest of the app —
  the developer that's credited on the VN page, not localizers, distributors,
  or re-release publishers.

  Selection rules:

    1. Keep only developers (`role` of `"developer"` or `"developer_publisher"`).
    2. Among developers, only keep those tied to the *earliest*
       `earliest_release_date`. This prevents producers added in later
       re-releases from being credited (e.g. Arc System Works on
       Fate/Stay Night).
    3. If no developers exist, return an empty list.

  Each row in `rows` must have at least `:role` (string) and
  `:earliest_release_date` (Date or nil) fields. Returns the filtered subset
  preserving input order — sort beforehand or after as needed.
  """
  def select_primary(rows) when is_list(rows) do
    devs = Enum.filter(rows, &dev_role?/1)

    if devs == [], do: [], else: filter_to_min_release_date(devs)
  end

  defp dev_role?(%{role: role}), do: role in ["developer", "developer_publisher"]
  defp dev_role?(_), do: false

  defp filter_to_min_release_date(devs) do
    min_date =
      devs
      |> Enum.map(& &1.earliest_release_date)
      |> Enum.reject(&is_nil/1)
      |> Enum.min(Date, fn -> nil end)

    case min_date do
      nil -> devs
      date -> Enum.filter(devs, &(&1.earliest_release_date == date))
    end
  end

  @doc """
  Gets a single producer.
  """
  def get_producer(id, opts \\ []) do
    case Producer |> maybe_filter_hidden(opts) |> Repo.get(id) do
      nil -> {:error, :not_found}
      producer -> {:ok, Repo.preload(producer, [:external_links, :producer_images])}
    end
  end

  @doc """
  Gets a single producer by slug.
  """
  def get_producer_by_slug(slug, opts \\ []) do
    case Producer |> maybe_filter_hidden(opts) |> where([p], p.slug == ^slug) |> Repo.one() do
      nil -> {:error, :not_found}
      producer -> {:ok, Repo.preload(producer, [:external_links, :producer_images])}
    end
  end

  @doc """
  Gets a single producer by VNDB ID.
  """
  def get_producer_by_vndb_id(vndb_id, opts \\ []) do
    case Producer
         |> maybe_filter_hidden(opts)
         |> where([p], p.vndb_id == ^vndb_id)
         |> Repo.one() do
      nil -> {:error, :not_found}
      producer -> {:ok, producer}
    end
  end

  @doc """
  Lists producers with pagination.
  """
  def list_producers(page \\ 1, page_size \\ 20, opts \\ []) do
    sort_by = Keyword.get(opts, :sort_by)
    filters = Keyword.get(opts, :filters, %{})

    query =
      Producer
      |> visible()
      |> apply_producer_filters(filters)
      |> apply_producer_sort(sort_by)

    {producers, pagination} =
      Kaguya.Pagination.paginate(query, page, page_size)

    # Preload external links for all producers
    producers =
      Repo.preload(producers, [:external_links, :producer_images])

    {:ok, %{items: producers, pagination: pagination}}
  end

  @doc """
  Gets visual novels for a producer with role information.
  Returns a list of maps with :visual_novel and :role keys. The :visual_novel
  is a projection containing only the fields used by the developer page card
  + Cover component — not a full VisualNovel struct.
  """
  def get_visual_novels_for_producer(producer_id, page \\ 1, page_size \\ 20) do
    query =
      from vp in VNProducer,
        join: vn in VisualNovel,
        on: vn.id == vp.visual_novel_id,
        where: vp.producer_id == ^producer_id,
        where: is_nil(vn.hidden_at),
        order_by: [desc: vn.ratings_count, desc: vn.release_date],
        select: %{
          visual_novel: %{
            id: vn.id,
            title: vn.title,
            slug: vn.slug,
            average_rating: vn.average_rating,
            ratings_count: vn.ratings_count,
            is_image_nsfw: vn.is_image_nsfw,
            is_image_suggestive: vn.is_image_suggestive,
            primary_image_id: vn.primary_image_id,
            temp_image_url: vn.temp_image_url
          },
          role: vp.role,
          earliest_release_date: vp.earliest_release_date
        }

    {items, pagination} = Kaguya.Pagination.paginate(query, page, page_size)

    {:ok, %{items: items, pagination: pagination}}
  end

  # ============================================================================
  # Search
  # ============================================================================

  alias Kaguya.Search

  @doc """
  Searches producers by name using Meilisearch.
  """
  def search_producers(query_string, page \\ 1, page_size \\ 20) do
    query = String.trim(query_string || "")

    with {:ok, response_body} <- Search.search_index("producers", query, page, page_size) do
      hits = Map.get(response_body, "hits", [])
      total = Map.get(response_body, "estimatedTotalHits", length(hits))

      items =
        Enum.map(hits, fn hit ->
          %{id: hit["id"], name: hit["name"], slug: hit["slug"]}
        end)

      {:ok,
       %{
         items: items,
         pagination: %{
           page: page,
           page_size: page_size,
           total_count: total,
           total_pages: max(1, ceil(total / page_size))
         }
       }}
    end
  end

  defp visible(query) do
    where(query, [p], is_nil(p.hidden_at))
  end

  @doc """
  Returns visible producers for sitemap indexing.

  Mirrors `list_visual_novels_for_sitemap/2` shape so `SitemapController` can
  pull paginated slug + updated_at maps without preloading images (Next.js
  `sitemap.ts` doesn't emit image sitemaps for producers).
  """
  def list_producers_for_sitemap(page \\ 1, page_size \\ 1000) do
    query =
      from(p in Producer,
        where: is_nil(p.hidden_at) and not is_nil(p.slug),
        order_by: [desc: p.updated_at, desc: p.id],
        select: %{slug: p.slug, updated_at: p.updated_at}
      )

    Kaguya.Pagination.paginate(query, page, page_size)
  end

  defp maybe_filter_hidden(query, opts) do
    if Keyword.get(opts, :include_hidden, false), do: query, else: visible(query)
  end

  # Private helpers

  defp apply_producer_filters(query, filters) when map_size(filters) == 0, do: query

  defp apply_producer_filters(query, filters) do
    query
    |> maybe_filter_by_type(filters["producer_type"] || filters[:producer_type])
    |> maybe_filter_by_language(filters["language"] || filters[:language])
  end

  defp maybe_filter_by_type(query, nil), do: query

  defp maybe_filter_by_type(query, type) when is_binary(type),
    do: where(query, [p], p.producer_type == ^type)

  defp maybe_filter_by_language(query, nil), do: query

  defp maybe_filter_by_language(query, lang) when is_binary(lang),
    do: where(query, [p], p.language == ^lang)

  defp apply_producer_sort(query, nil), do: order_by(query, [p], asc: p.name)
  defp apply_producer_sort(query, :name_asc), do: order_by(query, [p], asc: p.name)
  defp apply_producer_sort(query, :name_desc), do: order_by(query, [p], desc: p.name)
  defp apply_producer_sort(query, :newest), do: order_by(query, [p], desc: p.inserted_at)

  # ============================================================================
  # Edit / Revision Support
  # ============================================================================

  def get_for_edit(id) do
    case Repo.get(Producer, id) do
      nil -> nil
      producer -> Repo.preload(producer, [:external_links, :producer_images])
    end
  end

  @doc """
  Batch-loads multiple producers with the same preload set as
  `get_for_edit/1`. Used by the bulk revision writer to snapshot many
  entities in a single round-trip per preload instead of one per entity.
  """
  def batch_load_for_hist(ids) when is_list(ids) do
    from(p in Producer, where: p.id in ^ids)
    |> Repo.all()
    |> Repo.preload([:external_links, :producer_images])
  end

  def create_from_edit(attrs) do
    with {:ok, producer} <- %Producer{} |> Producer.changeset(attrs) |> Repo.insert(),
         :ok <- sync_external_links(producer, attrs) do
      reindex_search(producer)
      {:ok, producer}
    end
  end

  def apply_edit(producer, changes) do
    attrs =
      Map.take(changes, [
        :name,
        :description,
        :producer_type,
        :language,
        :primary_image_id,
        :is_image_nsfw,
        :is_image_suggestive
      ])

    with {:ok, producer} <- update_producer_fields(producer, attrs),
         :ok <- sync_external_links(producer, changes) do
      reindex_search(producer)
      {:ok, producer}
    end
  end

  defp update_producer_fields(producer, attrs) when attrs == %{}, do: {:ok, producer}

  defp update_producer_fields(producer, attrs) do
    producer |> Producer.changeset(attrs) |> Repo.update()
  end

  defp sync_external_links(producer, changes) do
    case Map.get(changes, :external_links) do
      nil ->
        :ok

      links when is_list(links) ->
        from(l in ProducerExternalLink, where: l.producer_id == ^producer.id) |> Repo.delete_all()
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        rows =
          Enum.map(links, fn l ->
            %{
              producer_id: producer.id,
              site: l.site,
              value: l.value,
              inserted_at: now,
              updated_at: now
            }
          end)

        if rows != [], do: Repo.insert_all(ProducerExternalLink, rows)
        :ok
    end
  end

  # ============================================================================
  # Revision _hist Support
  # ============================================================================

  alias Kaguya.Revisions.Hist.{ProducerHist, ProducerExternalLinkHist}

  # Every column on `producers_hist`.
  #
  # Intentionally excluded — denormalized counter / cache (matches VNDB pattern):
  #   follower_count — maintained by follow/unfollow actions, not user edits
  # Intentionally excluded — sync-managed external identifier: vndb_id
  @hist_fields [
    :name,
    :slug,
    :description,
    :producer_type,
    :language,
    :primary_image_id,
    :is_image_nsfw,
    :is_image_suggestive,
    :hidden_at,
    :is_locked
  ]

  # Slug is auto-derived and stable; kept in @hist_fields for revert but
  # excluded from field groups so it never surfaces in the diff.
  @field_groups %{
    "name" => [:name],
    "description" => [:description],
    "general" => [:producer_type, :language],
    "image" => [:primary_image_id, :is_image_nsfw, :is_image_suggestive],
    "links" => [:external_links],
    "moderation" => [:hidden_at, :is_locked]
  }

  def write_hist(change_id, producer) do
    Repo.insert_all(ProducerHist, [
      Map.take(producer, @hist_fields) |> Map.put(:change_id, change_id)
    ])

    link_rows =
      Enum.map(producer.external_links, fn l ->
        %{change_id: change_id, site: l.site, value: l.value}
      end)

    if link_rows != [], do: Repo.insert_all(ProducerExternalLinkHist, link_rows)
  end

  @doc """
  Bulk version of `write_hist/2` for seeding/backfill paths. Pairs must be
  `[{change_id, producer_with_preloads}, ...]` (preloaded with `:external_links`).
  """
  def bulk_write_hist([]), do: :ok

  def bulk_write_hist(pairs) when is_list(pairs) do
    main_rows =
      Enum.map(pairs, fn {change_id, producer} ->
        Map.take(producer, @hist_fields) |> Map.put(:change_id, change_id)
      end)

    chunked_insert_all(ProducerHist, main_rows)

    link_rows =
      Enum.flat_map(pairs, fn {change_id, producer} ->
        Enum.map(producer.external_links, fn l ->
          %{change_id: change_id, site: l.site, value: l.value}
        end)
      end)

    chunked_insert_all(ProducerExternalLinkHist, link_rows)

    :ok
  end

  defp chunked_insert_all(_module, []), do: :ok

  defp chunked_insert_all(module, rows) do
    rows
    |> Enum.chunk_every(1000)
    |> Enum.each(&Repo.insert_all(module, &1))

    :ok
  end

  def load_hist(change_id) do
    hist = Repo.one(from h in ProducerHist, where: h.change_id == ^change_id)
    links = Repo.all(from l in ProducerExternalLinkHist, where: l.change_id == ^change_id)
    %{hist: hist, links: links}
  end

  @doc """
  Batched version of `load_hist/1`. 2 queries for any number of change_ids.
  """
  def bulk_load_hist([]), do: %{}

  def bulk_load_hist(change_ids) when is_list(change_ids) do
    ids = Enum.uniq(change_ids)

    hists =
      Repo.all(from h in ProducerHist, where: h.change_id in ^ids) |> Map.new(&{&1.change_id, &1})

    links =
      Repo.all(from l in ProducerExternalLinkHist, where: l.change_id in ^ids)
      |> Enum.group_by(& &1.change_id)

    Map.new(ids, fn change_id ->
      {change_id, %{hist: Map.get(hists, change_id), links: Map.get(links, change_id, [])}}
    end)
  end

  def apply_hist(producer, hist_data) do
    # Bypass Producer.changeset on purpose: hist data includes slug + hidden_at
    # + is_locked which the user-edit changeset doesn't accept. Restoring with
    # Ecto.Changeset.change/2 brings back every snapshotted field verbatim.
    attrs = Map.take(hist_data.hist, @hist_fields)

    with {:ok, producer} <- producer |> Ecto.Changeset.change(attrs) |> Repo.update() do
      from(l in ProducerExternalLink, where: l.producer_id == ^producer.id) |> Repo.delete_all()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      rows =
        Enum.map(hist_data.links, fn l ->
          %{
            producer_id: producer.id,
            site: l.site,
            value: l.value,
            inserted_at: now,
            updated_at: now
          }
        end)

      if rows != [], do: Repo.insert_all(ProducerExternalLink, rows)

      reindex_search(producer)
      {:ok, producer}
    end
  end

  defp reindex_search(%Producer{} = producer) do
    if is_nil(producer.hidden_at) do
      SearchIndex.index_producers(producer)
    else
      SearchIndex.remove_producer(producer.id)
    end
  rescue
    e ->
      require Logger

      Logger.warning(
        "[Producers] Meilisearch reindex failed for #{producer.id}: #{Exception.message(e)}"
      )
  end

  def changed_field_groups(producer, changes) do
    @field_groups
    |> Enum.filter(fn {_group, fields} ->
      Enum.any?(fields, fn
        :external_links ->
          Map.has_key?(changes, :external_links)

        field ->
          Map.has_key?(changes, field) && Map.get(changes, field) != Map.get(producer, field)
      end)
    end)
    |> Enum.map(fn {group, _} -> group end)
    |> Enum.sort()
  end

  @doc """
  Builds producer image URLs from a primary producer image or temporary source URL.
  """
  def build_image_urls(%Producer{} = producer) do
    build_image_urls(%{primary_image_id: producer.primary_image_id})
  end

  def build_image_urls(%{} = attrs) do
    image_id = Map.get(attrs, :primary_image_id)

    if is_nil(image_id), do: %{}, else: build_cdn_image_urls(image_id)
  end

  def build_image_urls(nil), do: %{}

  defp build_cdn_image_urls(image_id) do
    %{
      small: Kaguya.Images.url_for_key(Kaguya.Images.key(:producer, image_id, "120w")),
      large: Kaguya.Images.url_for_key(Kaguya.Images.key(:producer, image_id, "360w"))
    }
  end
end
