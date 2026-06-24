defmodule Kaguya.VNTags do
  @moduledoc """
  Context for Visual Novel tags.
  Uses shared tags pool with VN-specific junction table.
  """

  import Ecto.Query
  alias Kaguya.Activities
  alias Kaguya.Cdn
  alias Kaguya.Repo
  alias Kaguya.CursorPagination
  alias Kaguya.Tags.Tag
  alias Kaguya.Tags.TagRelevance
  alias Kaguya.VisualNovels.{VisualNovel, VNTag}
  alias Kaguya.VNTags.VNTagVote

  # ============================================================================
  # Tag Queries
  # ============================================================================

  # Shared base filters for non-spoiler tags.
  # Useless tags (Setting, Style, Plot, Character descendants) are never imported
  # into the DB, so no displayability filter is needed at query time.
  defp displayable_tag_filters(query) do
    query
    |> where([vt, t], coalesce(vt.spoiler_level, t.default_spoiler_level) == 0)
    |> where([vt, t], vt.is_overruled == false)
  end

  # Live aggregation of Kaguya votes per (vn, tag). Used as a subquery in the
  # tag-listing queries so display rows can include `kaguya_vote_count` /
  # `kaguya_value_sum` / per-bucket counts without keeping denormalized
  # counters on `vn_tags`.
  #
  # `bucket_counts` is a length-6 int[] indexed by vote value (0=Not Relevant
  # … 5=Main Theme). The 6 FILTER aggregates run on the same already-grouped
  # rows, so the cost is one extra SUM per bucket — negligible vs. the JOIN.
  defp kaguya_aggregates_query do
    from v in VNTagVote,
      group_by: [v.visual_novel_id, v.tag_id],
      select: %{
        visual_novel_id: v.visual_novel_id,
        tag_id: v.tag_id,
        vote_count: count(v.id),
        value_sum: sum(v.value),
        bucket_counts:
          fragment(
            "ARRAY[
              count(*) FILTER (WHERE ? = 0)::int,
              count(*) FILTER (WHERE ? = 1)::int,
              count(*) FILTER (WHERE ? = 2)::int,
              count(*) FILTER (WHERE ? = 3)::int,
              count(*) FILTER (WHERE ? = 4)::int,
              count(*) FILTER (WHERE ? = 5)::int
            ]",
            v.value,
            v.value,
            v.value,
            v.value,
            v.value,
            v.value
          )
      }
  end

  @doc """
  Lists every tag with at least one non-spoiler, non-overruled VN vote,
  ordered by `vns_count` desc.

  Returns all categories *including* `:sexual`. Browse callers default to
  excluding sexual; the add-tag dialog opts in. Returning every category
  here keeps a single source of truth.

  `vns_count` is intentionally still bounded to non-spoiler, non-overruled
  votes so the popularity sort matches what users actually see on browse
  filters and tag chips.
  """
  def list_vn_tags do
    vns_count_query =
      from vt in VNTag,
        join: t in Tag,
        on: t.id == vt.tag_id,
        where: coalesce(vt.spoiler_level, t.default_spoiler_level) == 0,
        where: vt.is_overruled == false,
        group_by: vt.tag_id,
        select: %{tag_id: vt.tag_id, vns_count: count(vt.visual_novel_id)}

    tags =
      Tag
      |> join(:inner, [t], vc in subquery(vns_count_query), on: t.id == vc.tag_id)
      |> order_by([t, vc], desc: vc.vns_count, asc: t.name)
      |> select([t, vc], %{
        id: t.id,
        name: t.name,
        slug: t.slug,
        category: t.category,
        kind: t.kind,
        content_warning: t.content_warning,
        default_spoiler_level: t.default_spoiler_level,
        source: t.source,
        vns_count: vc.vns_count
      })
      |> Repo.all()

    {:ok, tags}
  end

  @doc """
  Searches VN tags for editor surfaces.

  Add-tag dialog ranking: exact name matches first,
  then prefix matches, then contains matches, with higher VN usage first
  inside each tier. Sexual tags are included because this is an editor
  surface, not a browse filter.
  """
  def search_tag_candidates(query, exclude_ids \\ [], limit \\ 15) do
    needle = query |> to_string() |> String.trim() |> String.downcase()

    if needle == "" do
      {:ok, []}
    else
      exclude_ids = MapSet.new(Enum.map(exclude_ids, &to_string/1))

      {:ok, tags} = list_vn_tags()

      tags =
        tags
        |> Enum.reject(fn tag ->
          MapSet.member?(exclude_ids, to_string(tag.id)) ||
            String.ends_with?(tag.name || "", "(obsolete)")
        end)
        |> Enum.flat_map(fn tag ->
          name = tag.name |> to_string() |> String.downcase()

          cond do
            name == needle -> [{tag, 0}]
            String.starts_with?(name, needle) -> [{tag, 1}]
            String.contains?(name, needle) -> [{tag, 2}]
            true -> []
          end
        end)
        |> Enum.sort_by(fn {tag, tier} -> {tier, -(tag.vns_count || 0), tag.name || ""} end)
        |> Enum.take(limit)
        |> Enum.map(fn {tag, _tier} -> tag end)

      {:ok, tags}
    end
  end

  @doc """
  Lists tags for a visual novel, ordered by relevance score.
  Excludes non-displayable tags, spoiler tags,
  and low-confidence tags (vote count below 25% of the VN's median vote count).
  """
  def list_tags_for_vn(visual_novel_id, user_id \\ nil) do
    # Adaptive vote threshold: floor(median_votes * 0.25)
    # On well-tagged VNs this cuts noise; on niche VNs (low median) it keeps everything.
    median_votes =
      from(vt in VNTag,
        join: t in Tag,
        on: t.id == vt.tag_id,
        where: vt.visual_novel_id == ^visual_novel_id,
        select: fragment("percentile_cont(0.5) WITHIN GROUP (ORDER BY ?)", vt.vndb_vote_count)
      )
      |> displayable_tag_filters()
      |> Repo.one() || 0

    vote_threshold = floor(median_votes * 0.25)

    query =
      from(vt in VNTag,
        join: t in Tag,
        on: t.id == vt.tag_id,
        where: vt.visual_novel_id == ^visual_novel_id,
        left_join: kv in subquery(kaguya_aggregates_query()),
        on: kv.visual_novel_id == vt.visual_novel_id and kv.tag_id == vt.tag_id,
        where:
          vt.vndb_vote_count >= ^vote_threshold or
            (not is_nil(kv.vote_count) and kv.vote_count > 0),
        order_by: [desc: vt.relevance_score],
        select: %{
          tag: t,
          relevance_score: vt.relevance_score,
          spoiler_level: 0,
          vndb_vote_count: vt.vndb_vote_count,
          vndb_avg_score: vt.vndb_avg_score,
          kaguya_vote_count: coalesce(kv.vote_count, 0),
          kaguya_value_sum: coalesce(kv.value_sum, 0),
          kaguya_bucket_counts: kv.bucket_counts
        }
      )
      |> displayable_tag_filters()

    tags = Repo.all(query)

    # Merge user's votes if authenticated
    tags =
      if user_id do
        votes = user_votes_for_vn(user_id, visual_novel_id)

        Enum.map(tags, fn tag ->
          tag_id = tag.tag.id
          Map.put(tag, :my_vote, Map.get(votes, tag_id))
        end)
      else
        Enum.map(tags, &Map.put(&1, :my_vote, nil))
      end

    {:ok, tags}
  end

  @doc """
  Batched variant of `list_tags_for_vn/2` — takes a list of VN ids and
  returns `%{vn_id => [tag_rows]}`, suitable for list-view callers that need
  batched tag loading. Every requested `vn_id` is present in the output map
  (empty list if the VN has no displayable tags).

  Behavior matches the single-VN version exactly: adaptive per-VN vote
  threshold (floor(median_votes * 0.25)), user-vote merge when
  `user_id` is given, displayability filter. Differences are purely
  about query count: three round-trips (thresholds, tag rows, user
  votes) regardless of how many VNs are requested, vs. the old
  per-VN 2-4 queries.
  """
  def list_tags_for_vns(_user_id, []), do: %{}

  def list_tags_for_vns(user_id, vn_ids) when is_list(vn_ids) do
    # One query: per-VN adaptive vote threshold (median_votes * 0.25 floor).
    thresholds =
      from(vt in VNTag,
        join: t in Tag,
        on: t.id == vt.tag_id,
        where: vt.visual_novel_id in ^vn_ids,
        group_by: vt.visual_novel_id,
        select:
          {vt.visual_novel_id,
           fragment(
             "floor(percentile_cont(0.5) WITHIN GROUP (ORDER BY ?) * 0.25)",
             vt.vndb_vote_count
           )}
      )
      |> displayable_tag_filters()
      |> Repo.all()
      |> Map.new(fn {vn_id, v} -> {vn_id, v || 0} end)

    # One query: all displayable tag rows for the whole VN set. We
    # fetch without the per-VN vote threshold filter and apply it in
    # Elixir land — pushing it into SQL would require either a
    # CASE/VALUES join (fragile) or an N-predicate WHERE (defeats the
    # point). 50 VNs × ~30 tag rows each is ~1500 rows in memory,
    # trivially small.
    rows =
      from(vt in VNTag,
        join: t in Tag,
        on: t.id == vt.tag_id,
        left_join: kv in subquery(kaguya_aggregates_query()),
        on: kv.visual_novel_id == vt.visual_novel_id and kv.tag_id == vt.tag_id,
        where: vt.visual_novel_id in ^vn_ids,
        order_by: [desc: vt.relevance_score],
        select: %{
          vn_id: vt.visual_novel_id,
          tag: t,
          relevance_score: vt.relevance_score,
          spoiler_level: 0,
          vndb_vote_count: vt.vndb_vote_count,
          vndb_avg_score: vt.vndb_avg_score,
          kaguya_vote_count: coalesce(kv.vote_count, 0),
          kaguya_value_sum: coalesce(kv.value_sum, 0),
          kaguya_bucket_counts: kv.bucket_counts
        }
      )
      |> displayable_tag_filters()
      |> Repo.all()
      |> Enum.filter(fn r ->
        threshold = Map.get(thresholds, r.vn_id, 0)
        r.vndb_vote_count >= threshold or r.kaguya_vote_count > 0
      end)

    # One query (only when authed): user's per-(vn, tag) votes across
    # the whole set. Key shape is {vn_id, tag_id} so the per-VN merge
    # loop below can look each one up in O(1).
    votes_by_vn_tag =
      if user_id do
        from(v in VNTagVote,
          where: v.user_id == ^user_id and v.visual_novel_id in ^vn_ids,
          select: {v.visual_novel_id, v.tag_id, v.value}
        )
        |> Repo.all()
        |> Map.new(fn {vn_id, tag_id, value} -> {{vn_id, tag_id}, value} end)
      else
        %{}
      end

    by_vn =
      rows
      |> Enum.group_by(& &1.vn_id)
      |> Map.new(fn {vn_id, tag_rows} ->
        tags =
          Enum.map(tag_rows, fn row ->
            row
            |> Map.delete(:vn_id)
            |> Map.put(:my_vote, Map.get(votes_by_vn_tag, {vn_id, row.tag.id}))
          end)

        {vn_id, tags}
      end)

    # Make sure every requested vn_id is present even if it had no
    # surviving rows — callers can then do a single `Map.get(map, vn_id, [])`
    # without worrying about missing keys.
    Enum.reduce(vn_ids, by_vn, fn vn_id, acc -> Map.put_new(acc, vn_id, []) end)
  end

  @doc """
  Gets or creates a tag by name.
  """
  def get_or_create_tag(name, opts \\ []) do
    slug = Slug.slugify(name)
    source = Keyword.get(opts, :source, "vndb")

    case Repo.get_by(Tag, slug: slug) do
      nil ->
        %Tag{}
        |> Tag.changeset(%{name: name, slug: slug, source: source})
        |> Repo.insert()

      tag ->
        {:ok, tag}
    end
  end

  @doc """
  Links a tag to a visual novel with relevance data.
  """
  def add_tag_to_vn(visual_novel_id, tag_id, attrs \\ %{}) do
    full_attrs =
      attrs
      |> Map.put(:visual_novel_id, visual_novel_id)
      |> Map.put(:tag_id, tag_id)

    %VNTag{}
    |> VNTag.changeset(full_attrs)
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:visual_novel_id, :tag_id])
  end

  @doc """
  Removes a tag from a visual novel.
  """
  def remove_tag_from_vn(visual_novel_id, tag_id) do
    query =
      from vt in VNTag,
        where: vt.visual_novel_id == ^visual_novel_id and vt.tag_id == ^tag_id

    case Repo.delete_all(query) do
      {1, _} -> {:ok, true}
      {0, _} -> {:error, :not_found}
    end
  end

  @doc """
  Updates tag relevance data for a VN.
  """
  def update_vn_tag(visual_novel_id, tag_id, attrs) do
    case Repo.get_by(VNTag, visual_novel_id: visual_novel_id, tag_id: tag_id) do
      nil ->
        {:error, :not_found}

      vn_tag ->
        vn_tag
        |> VNTag.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Sets all tags for a VN (replaces existing).
  Used for data imports.
  """
  def set_tags_for_vn(visual_novel_id, tag_data) when is_list(tag_data) do
    Repo.transact(fn ->
      # Remove existing tags and orphaned user votes
      from(v in VNTagVote, where: v.visual_novel_id == ^visual_novel_id)
      |> Repo.delete_all()

      from(vt in VNTag, where: vt.visual_novel_id == ^visual_novel_id)
      |> Repo.delete_all()

      # Add new tags
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      entries =
        for data <- tag_data do
          %{
            visual_novel_id: visual_novel_id,
            tag_id: data.tag_id,
            relevance_score: Map.get(data, :relevance_score, 0.0),
            vndb_vote_count: Map.get(data, :vndb_vote_count, 0),
            vndb_avg_score: Map.get(data, :vndb_avg_score),
            inserted_at: now,
            updated_at: now
          }
        end

      {count, _} = Repo.insert_all(VNTag, entries, on_conflict: :nothing)
      {:ok, count}
    end)
  end

  # ============================================================================
  # Tag Voting
  # ============================================================================

  @doc """
  Cast a graded vote on a tag for a VN. Value is 0..5
  (0 = Not Relevant / single downvote; 1..5 = Minor/Lesser/Moderate/Major/Main Theme).

  Creates the vn_tags row if it doesn't exist (tag suggestion). Idempotent —
  re-voting with the same value+spoiler is a no-op; changing either updates and
  triggers a relevance recompute.
  """
  def vote_vn_tag(user_id, visual_novel_id, tag_id, value, opts \\ [])
      when is_integer(value) and value in 0..5 do
    spoiler_level = Keyword.get(opts, :spoiler_level, 0)

    with {:ok, tag} <- validate_tag(tag_id),
         {:ok, _} <- validate_vn_exists(visual_novel_id),
         :ok <- check_not_overruled(visual_novel_id, tag_id) do
      result =
        Repo.transact(fn ->
          ensure_vn_tag_exists(visual_novel_id, tag_id)

          existing =
            Repo.get_by(VNTagVote,
              user_id: user_id,
              visual_novel_id: visual_novel_id,
              tag_id: tag_id
            )

          # `recompute?` mirrors the old `changed?` semantics — only re-run the
          # relevance aggregator when the *value* changes (spoiler-only changes
          # don't affect the score).
          # `emit?` is broader: any divergence from the existing row should
          # bump the activity feed (new vote, value change, spoiler change).
          {vote, recompute?, emit?} =
            case existing do
              nil ->
                {:ok, v} =
                  %VNTagVote{}
                  |> VNTagVote.changeset(%{
                    user_id: user_id,
                    visual_novel_id: visual_novel_id,
                    tag_id: tag_id,
                    value: value,
                    spoiler_level: spoiler_level
                  })
                  |> Repo.insert()

                {v, true, true}

              %{value: ^value, spoiler_level: ^spoiler_level} = v ->
                {v, false, false}

              %{value: ^value} = record ->
                # Same value, different spoiler_level — metadata only
                {:ok, v} =
                  record |> VNTagVote.changeset(%{spoiler_level: spoiler_level}) |> Repo.update()

                {v, false, true}

              record ->
                {:ok, v} =
                  record
                  |> VNTagVote.changeset(%{value: value, spoiler_level: spoiler_level})
                  |> Repo.update()

                {v, true, true}
            end

          if recompute?, do: TagRelevance.recompute_vn_tags_for_visual_novel(visual_novel_id)
          if emit?, do: record_voted_tag_activity(user_id, vote, tag, value, spoiler_level)
          {:ok, recompute?}
        end)

      with {:ok, changed?} <- result do
        if changed?, do: purge_vn_cdn(visual_novel_id)
        {:ok, true}
      end
    end
  end

  defp record_voted_tag_activity(user_id, vote, tag, value, spoiler_level) do
    Activities.upsert_activity(%{
      user_id: user_id,
      action: :voted_tag,
      entity_type: "tag_vote",
      entity_id: vote.id,
      metadata: %{
        tag_id: tag.id,
        tag_name: tag.name,
        tag_slug: tag.slug,
        value: value,
        spoiler_level: spoiler_level
      }
    })
  end

  defp validate_tag(tag_id) do
    case Repo.get(Tag, tag_id) do
      nil -> {:error, "Tag not found"}
      tag -> {:ok, tag}
    end
  end

  defp validate_vn_exists(visual_novel_id) do
    if Repo.exists?(from v in VisualNovel, where: v.id == ^visual_novel_id),
      do: {:ok, true},
      else: {:error, "Visual novel not found"}
  end

  defp check_not_overruled(visual_novel_id, tag_id) do
    case Repo.get_by(VNTag, visual_novel_id: visual_novel_id, tag_id: tag_id) do
      %{is_overruled: true} -> {:error, "Tag has been overruled by a moderator"}
      _ -> :ok
    end
  end

  @doc """
  Remove a user's vote on a tag for a VN.
  """
  def clear_vn_tag_vote(user_id, visual_novel_id, tag_id) do
    result =
      Repo.transact(fn ->
        case Repo.get_by(VNTagVote,
               user_id: user_id,
               visual_novel_id: visual_novel_id,
               tag_id: tag_id
             ) do
          nil ->
            {:ok, false}

          vote ->
            Repo.delete!(vote)
            TagRelevance.recompute_vn_tags_for_visual_novel(visual_novel_id)
            Activities.delete_activity(user_id, :voted_tag, "tag_vote", vote.id)
            {:ok, true}
        end
      end)

    with {:ok, changed?} <- result do
      if changed?, do: purge_vn_cdn(visual_novel_id)
      {:ok, true}
    end
  end

  @doc """
  Cursor-paginated list of users who voted on a tag for a VN, newest first.

  Returns rows of `%{user, value, voted_at}` for voter popovers. Includes
  downvotes (value=0) so
  the popover can show the full distribution; the frontend chooses how
  to label them.
  """
  def list_voters_for_vn_tag(visual_novel_id, tag_id, opts \\ []) do
    cursor = Keyword.get(opts, :cursor)
    limit = Keyword.get(opts, :limit, 20)
    value_filter = Keyword.get(opts, :value)

    # Two cursor columns (inserted_at + id) so rows with identical
    # timestamps still paginate deterministically — same shape as
    # Social.list_producer_followers, but with the vote's UUID since
    # vn_tag_votes has no other tiebreaker.
    base =
      from v in VNTagVote,
        join: u in assoc(v, :user),
        where: v.visual_novel_id == ^visual_novel_id and v.tag_id == ^tag_id,
        select: %{
          id: v.id,
          user: u,
          value: v.value,
          voted_at: v.inserted_at,
          inserted_at: v.inserted_at
        }

    query =
      if is_integer(value_filter),
        do: from([v] in base, where: v.value == ^value_filter),
        else: base

    {items, next_cursor, has_next} =
      CursorPagination.paginate(
        query,
        [:inserted_at, :id],
        [:datetime, :string],
        cursor,
        limit,
        :desc
      )

    {:ok, %{items: items, next_cursor: next_cursor, has_next: has_next}}
  end

  @doc """
  Cursor-paginated list of all tag votes cast by a single user. Defaults
  to newest first; pass `:order, :asc` for oldest first. Optional
  `:value` filters to a single bucket (0..5).
  """
  def list_tag_votes_by_user(user_id, opts \\ []) do
    cursor = Keyword.get(opts, :cursor)
    limit = Keyword.get(opts, :limit, 20)
    order = Keyword.get(opts, :order, :desc)
    value_filter = Keyword.get(opts, :value)

    base =
      from v in VNTagVote,
        join: vn in assoc(v, :visual_novel),
        join: t in assoc(v, :tag),
        where: v.user_id == ^user_id,
        select: %{
          id: v.id,
          visual_novel: vn,
          tag: t,
          value: v.value,
          voted_at: v.inserted_at,
          inserted_at: v.inserted_at
        }

    query =
      if is_integer(value_filter),
        do: from([v] in base, where: v.value == ^value_filter),
        else: base

    {items, next_cursor, has_next} =
      CursorPagination.paginate(
        query,
        [:inserted_at, :id],
        [:datetime, :string],
        cursor,
        limit,
        order
      )

    {:ok, %{items: items, next_cursor: next_cursor, has_next: has_next}}
  end

  @doc """
  Total number of tag votes cast by a user. Used for header chip
  discoverability — only render the link when this is > 0.
  """
  def count_tag_votes_by_user(user_id) do
    Repo.one(from v in VNTagVote, where: v.user_id == ^user_id, select: count(v.id)) || 0
  end

  @doc """
  Get a user's votes for tags on a VN. Returns map of `tag_id => value` (0..5).
  """
  def user_votes_for_vn(user_id, visual_novel_id) do
    from(v in VNTagVote,
      where: v.user_id == ^user_id and v.visual_novel_id == ^visual_novel_id,
      select: {v.tag_id, v.value}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp ensure_vn_tag_exists(visual_novel_id, tag_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert_all(
      VNTag,
      [%{visual_novel_id: visual_novel_id, tag_id: tag_id, inserted_at: now, updated_at: now}],
      on_conflict: :nothing,
      conflict_target: [:visual_novel_id, :tag_id]
    )
  end

  # ============================================================================
  # Moderation
  # ============================================================================

  @doc """
  Overrule a tag on a VN — hides it from display regardless of votes.
  Mod/admin only.
  """
  def overrule_vn_tag(visual_novel_id, tag_id, mod_id) do
    result =
      case Repo.get_by(VNTag, visual_novel_id: visual_novel_id, tag_id: tag_id) do
        nil ->
          {:error, "Tag not applied to this visual novel"}

        vn_tag ->
          vn_tag
          |> VNTag.changeset(%{is_overruled: true, overruled_by: mod_id})
          |> Repo.update()
      end

    with {:ok, _} = ok <- result do
      purge_vn_cdn(visual_novel_id)
      ok
    end
  end

  @doc """
  Remove an overrule on a tag for a VN — restores it to normal vote-based display.
  """
  def remove_vn_tag_overrule(visual_novel_id, tag_id) do
    result =
      case Repo.get_by(VNTag, visual_novel_id: visual_novel_id, tag_id: tag_id) do
        nil ->
          {:error, "Tag not applied to this visual novel"}

        vn_tag ->
          vn_tag
          |> VNTag.changeset(%{is_overruled: false, overruled_by: nil})
          |> Repo.update()
      end

    with {:ok, _} = ok <- result do
      purge_vn_cdn(visual_novel_id)
      ok
    end
  end

  defp purge_vn_cdn(vn_id) do
    slug = Repo.one(from v in VisualNovel, where: v.id == ^vn_id, select: v.slug)
    if slug, do: Cdn.purge_vn_cache(slug)
  end

  # ============================================================================
  # Search by Tag
  # ============================================================================

  @doc """
  Lists visual novels with a specific tag.
  """
  def list_vns_by_tag(tag_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    offset = Keyword.get(opts, :offset, 0)

    query =
      from vn in VisualNovel,
        join: vt in VNTag,
        on: vt.visual_novel_id == vn.id,
        where: vt.tag_id == ^tag_id,
        where: vt.is_overruled == false,
        order_by: [desc: vt.relevance_score, desc: vn.average_rating],
        limit: ^limit,
        offset: ^offset

    {:ok, Repo.all(query)}
  end
end
