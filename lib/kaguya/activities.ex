defmodule Kaguya.Activities do
  @moduledoc """
  Context for user activity feed.

  Records denormalized activity events (actor + verb + object + metadata)
  for chronological, cursor-paginated display on user profiles.
  """

  import Ecto.Query
  require Logger

  alias Kaguya.Repo
  alias Kaguya.Activities.UserActivity
  alias Kaguya.Activities.GroupedFeed
  alias Kaguya.CursorPagination
  alias Kaguya.Users.User
  alias Kaguya.Reviews.Review
  alias Kaguya.VisualNovels.VisualNovel

  # Home feed buffer sizing. We fetch more raw rows than the requested
  # entry limit so post-query grouping can still hit `limit` entries
  # in pathological "many likes from one user" cases.
  @home_limit_max 64
  @home_buffer_max 256
  @home_buffer_floor_extra 32
  @home_buffer_multiplier 3

  @doc """
  Records a user activity. Logs a warning on failure but does not raise.

  Idempotent — `(user_id, action, entity_type, entity_id)` collisions are
  silently dropped via `on_conflict: :nothing`. First-write-wins semantics.
  Use this for events that are immutable once recorded (likes, follows,
  reviewed, comments, created_list, etc.).

  For "re-event" semantics where the latest emission should win — and the
  row's metadata + timestamp should refresh atomically — use
  `upsert_activity/1` instead.
  """
  def record_activity(attrs) do
    case %UserActivity{}
         |> UserActivity.changeset(attrs)
         |> Repo.insert(
           on_conflict: :nothing,
           conflict_target: [:user_id, :action, :entity_type, :entity_id]
         ) do
      {:ok, activity} ->
        {:ok, activity}

      {:error, changeset} = error ->
        Logger.warning("Failed to record activity: #{inspect(changeset.errors)}")
        error
    end
  end

  @doc """
  Inserts or updates an activity row keyed by
  `(user_id, action, entity_type, entity_id)`. On conflict, replaces metadata
  and bumps `inserted_at` + `updated_at` atomically (last writer wins).

  Use for "re-event" activities where each emission should refresh the row:
  tag re-votes, edits where we want one-row-per-(user, entity), etc.

  Atomic — unlike the legacy delete-then-insert pattern (`:rated`,
  `:status_changed`), concurrent emissions are both reflected: the second
  writer's metadata wins instead of being silently swallowed by
  `on_conflict: :nothing`.
  """
  def upsert_activity(attrs) do
    case %UserActivity{}
         |> UserActivity.changeset(attrs)
         |> Repo.insert(
           on_conflict: {:replace, [:metadata, :inserted_at, :updated_at]},
           conflict_target: [:user_id, :action, :entity_type, :entity_id],
           # `:returning` ensures the returned struct reflects the row's actual
           # state post-upsert. Without it Ecto returns the changeset's
           # auto-generated id, which is *discarded* by the conflict update —
           # callers that follow up with the returned id would be reading a
           # ghost id that doesn't exist in the DB.
           returning: true
         ) do
      {:ok, activity} ->
        {:ok, activity}

      {:error, changeset} = error ->
        Logger.warning("Failed to upsert activity: #{inspect(changeset.errors)}")
        error
    end
  end

  @doc """
  Lists activities for a user, cursor-paginated by inserted_at (newest first).

  Accepts `:viewer_id` in opts — private-list activities are always hidden.
  """
  def list_activities_for_user(user_id, opts \\ []) do
    cursor = Keyword.get(opts, :cursor)
    limit = Keyword.get(opts, :limit, 20)
    exclude_actions = Keyword.get(opts, :exclude_actions, [])
    viewer_id = Keyword.get(opts, :viewer_id)

    query = from(a in UserActivity, as: :activity, where: a.user_id == ^user_id)

    query =
      case exclude_actions do
        [] -> query
        actions -> query |> where([a], a.action not in ^actions)
      end

    allowed_categories = Keyword.get(opts, :allowed_categories, [:vn])
    screenshot_prefs = Keyword.get(opts, :screenshot_prefs, %{})

    query
    |> exclude_private_list_activities(viewer_id)
    |> exclude_hidden_content_activities(viewer_id)
    |> exclude_category_activities(allowed_categories)
    |> exclude_flagged_screenshot_activities(screenshot_prefs)
    |> paginate_activities(cursor, limit)
  end

  @doc """
  Lists global home-feed activities as grouped entries (newest first).

  Returns `{:ok, %{entries: [...], next_cursor: ..., has_next: ...}}`
  where each entry summarises consecutive same-user/action/context rows
  per `Kaguya.Activities.GroupedFeed`.
  """
  def list_global_activities(viewer_id \\ nil, cursor \\ nil, limit \\ 20, opts \\ []) do
    allowed_categories = Keyword.get(opts, :allowed_categories, [:vn])
    screenshot_prefs = Keyword.get(opts, :screenshot_prefs, %{})
    exclude_actions = Keyword.get(opts, :exclude_actions, [])

    from(a in UserActivity, as: :activity)
    |> exclude_actions(exclude_actions)
    |> exclude_private_list_activities(viewer_id)
    |> exclude_post_activities()
    |> exclude_hidden_content_activities(viewer_id)
    |> exclude_category_activities(allowed_categories)
    |> exclude_flagged_screenshot_activities(screenshot_prefs)
    |> paginate_grouped(cursor, limit)
  end

  @doc """
  Lists home-feed activities from users the viewer follows, as grouped entries.
  """
  def list_following_activities(viewer_id, cursor \\ nil, limit \\ 20, opts \\ []) do
    allowed_categories = Keyword.get(opts, :allowed_categories, [:vn])
    screenshot_prefs = Keyword.get(opts, :screenshot_prefs, %{})
    exclude_actions = Keyword.get(opts, :exclude_actions, [])

    following_ids =
      from(uf in Kaguya.Social.UserFollow,
        where: uf.follower_id == ^viewer_id,
        select: uf.followed_id
      )

    from(a in UserActivity, as: :activity)
    |> where([a], a.user_id in subquery(following_ids))
    |> exclude_actions(exclude_actions)
    |> exclude_private_list_activities(viewer_id)
    |> exclude_post_activities()
    |> exclude_hidden_content_activities(viewer_id)
    |> exclude_category_activities(allowed_categories)
    |> exclude_flagged_screenshot_activities(screenshot_prefs)
    |> paginate_grouped(cursor, limit)
  end

  # ---------------------------------------------------------------------------
  # Private-list filtering
  # ---------------------------------------------------------------------------

  defp exclude_hidden_content_activities(query, viewer_id) do
    # Schemas with only hidden_at — entity_id is the row id directly.
    hidden_only_types = [
      {"review", Kaguya.Reviews.Review},
      {"review_comment", Kaguya.Reviews.ReviewComment},
      {"list", Kaguya.Lists.List},
      {"list_comment", Kaguya.Lists.ListComment}
    ]

    # Schemas with both hidden_at and deleted_at.
    hidden_and_deleted_types = [
      {"post", Kaguya.Discussions.Post},
      {"post_comment", Kaguya.Discussions.Comment}
    ]

    # Revision activities — entity_id is the change.id; the live entity is
    # at metadata.target_entity_id. Exclude when the target is hidden.
    revision_target_types = [
      {"visual_novel", Kaguya.VisualNovels.VisualNovel},
      {"character", Kaguya.Characters.Character},
      {"producer", Kaguya.Producers.Producer},
      {"release", Kaguya.Releases.Release},
      {"series", Kaguya.VisualNovels.Series}
    ]

    query
    |> exclude_by_hidden(hidden_only_types, viewer_id)
    |> exclude_by_hidden_or_deleted(hidden_and_deleted_types, viewer_id)
    |> exclude_by_revision_target_hidden(revision_target_types)
    |> exclude_tag_vote_when_vn_hidden()
    |> exclude_quote_when_vn_hidden()
    |> exclude_release_when_parent_vn_hidden()
  end

  # Filters revision activities (entity_type ∈ {visual_novel, character,
  # producer, release}) when their target entity is hidden. The target id
  # lives at `metadata->>'target_entity_id'` since `entity_id` is the change
  # row id, not the entity id.
  defp exclude_by_revision_target_hidden(query, content_types) do
    Enum.reduce(content_types, query, fn {entity_type, schema}, q ->
      correlated = revision_target_hidden_exists(schema)

      where(q, [a], not (a.entity_type == ^entity_type and exists(subquery(correlated))))
    end)
  end

  defp revision_target_hidden_exists(schema) do
    from(e in schema,
      where: not is_nil(e.hidden_at),
      where:
        e.id ==
          fragment(
            "(?->>'target_entity_id')::uuid",
            parent_as(:activity).metadata
          )
    )
  end

  # Tag-vote activities resolve to the parent VN; hide them when the VN is
  # hidden (the vote row itself has no hidden_at).
  defp exclude_tag_vote_when_vn_hidden(query) do
    where(
      query,
      [a],
      not (a.entity_type == "tag_vote" and
             exists(
               from(tv in Kaguya.VNTags.VNTagVote,
                 join: vn in VisualNovel,
                 on: vn.id == tv.visual_novel_id,
                 where: tv.id == parent_as(:activity).entity_id,
                 where: not is_nil(vn.hidden_at)
               )
             ))
    )
  end

  # Quote activities (added/liked) — same shape: hide when parent VN is hidden.
  defp exclude_quote_when_vn_hidden(query) do
    where(
      query,
      [a],
      not (a.entity_type == "quote" and
             exists(
               from(q in Kaguya.Characters.Quote,
                 join: vn in VisualNovel,
                 on: vn.id == q.visual_novel_id,
                 where: q.id == parent_as(:activity).entity_id,
                 where: not is_nil(vn.hidden_at)
               )
             ))
    )
  end

  # Release revision activities: also hide when the parent VN is hidden, even
  # if the release row itself isn't (the release-target check above only
  # catches release.hidden_at; this layer catches the parent).
  defp exclude_release_when_parent_vn_hidden(query) do
    where(
      query,
      [a],
      not (a.entity_type == "release" and
             exists(
               from(r in Kaguya.Releases.Release,
                 join: vn in VisualNovel,
                 on: vn.id == r.visual_novel_id,
                 where:
                   r.id ==
                     fragment(
                       "(?->>'target_entity_id')::uuid",
                       parent_as(:activity).metadata
                     ),
                 where: not is_nil(vn.hidden_at)
               )
             ))
    )
  end

  defp exclude_by_hidden(query, content_types, viewer_id) do
    Enum.reduce(content_types, query, fn {entity_type, schema}, q ->
      correlated = hidden_content_exists(schema, viewer_id)

      where(q, [a], not (a.entity_type == ^entity_type and exists(subquery(correlated))))
    end)
  end

  defp exclude_by_hidden_or_deleted(query, content_types, viewer_id) do
    Enum.reduce(content_types, query, fn {entity_type, schema}, q ->
      correlated = hidden_or_deleted_content_exists(schema, viewer_id)

      where(q, [a], not (a.entity_type == ^entity_type and exists(subquery(correlated))))
    end)
  end

  defp hidden_content_exists(schema, nil) do
    from(r in schema,
      where: not is_nil(r.hidden_at),
      where: r.id == parent_as(:activity).entity_id
    )
  end

  defp hidden_content_exists(schema, viewer_id) do
    from(r in schema,
      where: not is_nil(r.hidden_at),
      where: r.user_id != ^viewer_id,
      where: r.id == parent_as(:activity).entity_id
    )
  end

  defp hidden_or_deleted_content_exists(schema, nil) do
    from(r in schema,
      where: not is_nil(r.hidden_at) or not is_nil(r.deleted_at),
      where: r.id == parent_as(:activity).entity_id
    )
  end

  defp hidden_or_deleted_content_exists(schema, viewer_id) do
    from(r in schema,
      where: not is_nil(r.hidden_at) or not is_nil(r.deleted_at),
      where: r.user_id != ^viewer_id,
      where: r.id == parent_as(:activity).entity_id
    )
  end

  # Posts surface in their own places (vn feed, /discussions, profile activity).
  # The home activity sidebar stays focused on review/list/rating signals.
  defp exclude_post_activities(query) do
    where(query, [a], a.entity_type not in ["post", "post_comment"])
  end

  defp exclude_actions(query, []), do: query

  defp exclude_actions(query, actions) when is_list(actions) do
    where(query, [a], a.action not in ^actions)
  end

  # Drop liked_screenshot activities whose target is flagged and the viewer
  # hasn't opted in to seeing that class of screenshot. Metadata fields
  # `screenshot_is_nsfw` and `screenshot_is_brutal` are written at activity
  # record time by Screenshots.record_liked_screenshot_activity/2; older
  # rows without these fields are pre-WD14 (always Safe+Tame) and fall
  # through unfiltered.
  #
  # `prefs` is a map — typically `%{show_nsfw: bool, show_brutal: bool}`.
  # Missing keys default to false (hide). `nil` viewer also defaults to hide.
  defp exclude_flagged_screenshot_activities(query, prefs) when is_map(prefs) do
    show_nsfw = Map.get(prefs, :show_nsfw, false)
    show_brutal = Map.get(prefs, :show_brutal, false)

    cond do
      show_nsfw and show_brutal ->
        query

      show_nsfw ->
        where(
          query,
          [a],
          not (a.action == :liked_screenshot and
                 fragment("?->>'screenshot_is_brutal' = 'true'", a.metadata))
        )

      show_brutal ->
        where(
          query,
          [a],
          not (a.action == :liked_screenshot and
                 fragment("?->>'screenshot_is_nsfw' = 'true'", a.metadata))
        )

      true ->
        where(
          query,
          [a],
          not (a.action == :liked_screenshot and
                 (fragment("?->>'screenshot_is_nsfw' = 'true'", a.metadata) or
                    fragment("?->>'screenshot_is_brutal' = 'true'", a.metadata)))
        )
    end
  end

  defp exclude_flagged_screenshot_activities(query, _), do: query

  defp exclude_private_list_activities(query, _viewer_id) do
    query
    |> where(
      [a],
      fragment(
        "NOT (? = 'list' AND EXISTS (SELECT 1 FROM lists WHERE id = ? AND NOT is_public))",
        a.entity_type,
        a.entity_id
      )
    )
    |> where(
      [a],
      fragment(
        "NOT (? = 'list_comment' AND EXISTS (SELECT 1 FROM lists WHERE id = (? ->> 'parent_entity_id')::uuid AND NOT is_public))",
        a.entity_type,
        a.metadata
      )
    )
  end

  # Exclude activities for VNs whose title_category is not in the allowed list.
  # Uses the metadata->>'vn_id' field to look up the VN's category.
  defp exclude_category_activities(query, allowed) when length(allowed) == 3, do: query

  defp exclude_category_activities(query, allowed) do
    excluded_vn_ids =
      from(vn in VisualNovel,
        where: vn.title_category not in ^allowed,
        select: type(vn.id, :string)
      )

    allowed_strings = Enum.map(allowed, &to_string/1)

    query
    |> where(
      [a],
      is_nil(fragment("? ->> 'vn_id'", a.metadata)) or
        fragment("? ->> 'vn_id'", a.metadata) not in subquery(excluded_vn_ids)
    )
    |> where(
      [a],
      fragment(
        "NOT (? = 'list' AND NOT EXISTS (SELECT 1 FROM list_items li JOIN visual_novels vn ON vn.id = li.visual_novel_id WHERE li.list_id = ? AND vn.title_category = ANY(?)))",
        a.entity_type,
        a.entity_id,
        ^allowed_strings
      )
    )
  end

  defp paginate_activities(query, cursor, limit) do
    query
    |> CursorPagination.paginate([:inserted_at, :id], [:datetime, :string], cursor, limit, :desc)
    |> format_response()
  end

  # Buffer-fetch raw rows, group them, slice to `limit` entries, anchor
  # the next cursor on the last raw row consumed.
  defp paginate_grouped(query, cursor, limit) do
    limit = limit |> max(1) |> min(@home_limit_max)

    buffer_limit =
      (limit * @home_buffer_multiplier)
      |> max(limit + @home_buffer_floor_extra)
      |> min(@home_buffer_max)

    decoded = CursorPagination.decode_cursor(cursor, [:datetime, :string])

    rows =
      query
      |> apply_activity_cursor(decoded)
      |> order_by([a], desc: a.inserted_at, desc: a.id)
      |> limit(^buffer_limit)
      |> Repo.all()

    all_entries = GroupedFeed.group_entries(rows)
    rows_filled = length(rows) >= buffer_limit

    {kept, rest} = Enum.split(all_entries, limit)
    has_next = rest != [] or rows_filled

    next_cursor =
      if has_next and kept != [] do
        last = List.last(kept).last_member
        CursorPagination.encode_cursor({last.inserted_at, last.id})
      else
        nil
      end

    {:ok, %{entries: kept, next_cursor: next_cursor, has_next: has_next}}
  end

  defp apply_activity_cursor(query, nil), do: query

  defp apply_activity_cursor(query, {ts, id}) do
    where(
      query,
      [a],
      a.inserted_at < ^ts or (a.inserted_at == ^ts and a.id < ^id)
    )
  end

  @doc """
  Deletes all activities for a given entity (e.g. when a review or list is deleted).
  """
  def delete_activities_for_entity(entity_type, entity_id) do
    from(a in UserActivity,
      where: a.entity_type == ^entity_type and a.entity_id == ^entity_id
    )
    |> Repo.delete_all()
  end

  @doc """
  Deletes a specific activity by user, action, entity_type, and entity_id.
  Used for targeted cleanup (e.g. unlike, remove rating).
  """
  def delete_activity(user_id, action, entity_type, entity_id) do
    from(a in UserActivity,
      where:
        a.user_id == ^user_id and
          a.action == ^action and
          a.entity_type == ^entity_type and
          a.entity_id == ^entity_id
    )
    |> Repo.delete_all()
  end

  @doc """
  Batch-loads associated records (reviews, lists, users) onto activity items
  to avoid N+1 queries in activity feeds.

  Used by the per-user activity feed (`:items` shape).
  """
  def preload_associations(%{items: []} = connection), do: connection

  def preload_associations(%{items: items} = connection) do
    %{connection | items: load_associations(items)}
  end

  @doc """
  Same idea as `preload_associations/1`, but for the home-feed `:entries`
  shape. Preloads across every member of every entry in one batched pass,
  then re-attaches loaded rows by id.
  """
  def preload_entry_associations(%{entries: []} = result), do: result

  def preload_entry_associations(%{entries: entries} = result) do
    rows = Enum.flat_map(entries, & &1.members)
    by_id = rows |> load_associations() |> Map.new(&{&1.id, &1})

    loaded =
      Enum.map(entries, fn entry ->
        loaded_members = Enum.map(entry.members, &Map.get(by_id, &1.id, &1))
        %{entry | members: loaded_members, representative: hd(loaded_members)}
      end)

    %{result | entries: loaded}
  end

  defp load_associations([]), do: []

  defp load_associations(items) do
    review_ids =
      items
      |> Enum.flat_map(&review_id_for/1)
      |> Enum.uniq()

    list_ids =
      items
      |> Enum.filter(&(&1.action in [:created_list, :liked_list]))
      |> Enum.map(& &1.entity_id)

    followed_user_ids =
      items
      |> Enum.filter(&(&1.action == :followed and &1.entity_type == "user"))
      |> Enum.map(& &1.entity_id)

    followed_producer_ids =
      items
      |> Enum.filter(&(&1.action == :followed and &1.entity_type == "producer"))
      |> Enum.map(& &1.entity_id)

    actor_ids =
      items
      |> Enum.map(& &1.user_id)
      |> Enum.uniq()

    reviews_map = batch_load(Review, review_ids)
    lists_map = batch_load(Kaguya.Lists.List, list_ids)
    producers_map = batch_load(Kaguya.Producers.Producer, followed_producer_ids)
    entity_refs_map = load_entity_refs(items)

    # Merge all user IDs into one batch: actors, followed users, review authors, list creators.
    # This eliminates duplicate user loads for nested review.user / list.user.
    review_user_ids = reviews_map |> Map.values() |> Enum.map(& &1.user_id)
    list_user_ids = lists_map |> Map.values() |> Enum.map(& &1.user_id)
    all_user_ids = Enum.uniq(actor_ids ++ followed_user_ids ++ review_user_ids ++ list_user_ids)

    users_map = batch_load(User, all_user_ids)

    # Batch the VNs referenced by activity reviews so downstream normalizers
    # don't fall back to per-review Repo.preload(:visual_novel) (N+1).
    review_vn_ids = reviews_map |> Map.values() |> Enum.map(& &1.visual_novel_id) |> Enum.uniq()
    review_vns_map = batch_load(Kaguya.VisualNovels.VisualNovel, review_vn_ids)

    # Attach preloaded users + VNs to reviews and users to lists so Repo.preload no-ops.
    reviews_map =
      Map.new(reviews_map, fn {id, review} ->
        {id,
         %{
           review
           | user: Map.get(users_map, review.user_id),
             visual_novel: Map.get(review_vns_map, review.visual_novel_id)
         }}
      end)

    lists_map =
      Map.new(lists_map, fn {id, list} ->
        {id, %{list | user: Map.get(users_map, list.user_id)}}
      end)

    Enum.map(items, fn activity ->
      activity
      |> attach_actor(users_map)
      |> attach_review(reviews_map)
      |> attach_list(lists_map)
      |> attach_followed_user(users_map)
      |> attach_followed_producer(producers_map)
      |> attach_entity_ref(entity_refs_map)
    end)
  end

  # ---------------------------------------------------------------------------
  # Entity ref preloading
  # ---------------------------------------------------------------------------
  #
  # Activities that point at an entity which can change (rename, hidden) should
  # resolve their display data live rather than from frozen metadata. The
  # virtual `:entity_ref` field carries `{entity_type, entity_id, name, slug,
  # image_url, is_hidden, parent_vn_slug}` populated here in one batched pass
  # per entity_type.
  #
  # Phase 1 covers `"tag_vote"` only (dereferences to the parent VN).
  # Later phases extend to `"visual_novel"`, `"character"`, `"producer"`,
  # `"release"`, `"quote"`. Activities whose `entity_type` is not handled
  # here pass through unchanged — `entity_ref` stays `nil` and renderers
  # continue using metadata.

  defp load_entity_refs(items) do
    items
    |> Enum.group_by(& &1.entity_type)
    |> Enum.reduce(%{}, fn {entity_type, group}, acc ->
      Map.merge(acc, build_entity_refs(entity_type, group))
    end)
  end

  # vn_tag_vote.id → parent VN ref
  defp build_entity_refs("tag_vote", []), do: %{}

  defp build_entity_refs("tag_vote", items) do
    vote_ids = items |> Enum.map(& &1.entity_id) |> Enum.uniq()

    from(v in Kaguya.VNTags.VNTagVote,
      join: vn in VisualNovel,
      on: vn.id == v.visual_novel_id,
      where: v.id in ^vote_ids,
      select: {v.id, vn}
    )
    |> Repo.all()
    |> Map.new(fn {vote_id, vn} ->
      {{"tag_vote", vote_id}, build_vn_ref("tag_vote", vote_id, vn)}
    end)
  end

  # vn_quote.id → parent VN ref
  defp build_entity_refs("quote", []), do: %{}

  defp build_entity_refs("quote", items) do
    quote_ids = items |> Enum.map(& &1.entity_id) |> Enum.uniq()

    from(q in Kaguya.Characters.Quote,
      join: vn in VisualNovel,
      on: vn.id == q.visual_novel_id,
      where: q.id in ^quote_ids,
      select: {q.id, vn}
    )
    |> Repo.all()
    |> Map.new(fn {quote_id, vn} ->
      {{"quote", quote_id}, build_vn_ref("quote", quote_id, vn)}
    end)
  end

  # Revision activities: entity_id is the change.id, with the live entity's id
  # carried in `metadata.target_entity_id`. Dereference one hop via metadata.
  defp build_entity_refs("visual_novel", items),
    do:
      build_revision_refs("visual_novel", Kaguya.VisualNovels.VisualNovel, items, &build_vn_ref/3)

  defp build_entity_refs("character", items),
    do:
      build_revision_refs("character", Kaguya.Characters.Character, items, &build_character_ref/3)

  defp build_entity_refs("producer", items),
    do: build_revision_refs("producer", Kaguya.Producers.Producer, items, &build_producer_ref/3)

  defp build_entity_refs("release", items), do: build_release_refs(items)

  defp build_entity_refs("series", items),
    do: build_revision_refs("series", Kaguya.VisualNovels.Series, items, &build_series_ref/3)

  defp build_entity_refs(_entity_type, _items), do: %{}

  defp build_revision_refs(_entity_type, _schema, [], _builder), do: %{}

  defp build_revision_refs(entity_type, schema, items, builder) do
    items_by_target =
      items
      |> Enum.map(fn item -> {target_entity_id(item), item} end)
      |> Enum.reject(fn {target_id, _item} -> is_nil(target_id) end)

    target_ids = items_by_target |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

    if target_ids == [] do
      %{}
    else
      entities_by_id =
        from(e in schema, where: e.id in ^target_ids)
        |> Repo.all()
        |> Map.new(&{&1.id, &1})

      Map.new(items_by_target, fn {target_id, item} ->
        ref =
          case Map.get(entities_by_id, target_id) do
            nil -> nil
            entity -> builder.(entity_type, item.entity_id, entity)
          end

        {{entity_type, item.entity_id}, ref}
      end)
      |> Map.reject(fn {_, v} -> is_nil(v) end)
    end
  end

  # Releases need their parent VN's slug for navigation (releases have no
  # standalone page). Same shape as build_revision_refs but with a join.
  defp build_release_refs([]), do: %{}

  defp build_release_refs(items) do
    items_by_target =
      items
      |> Enum.map(fn item -> {target_entity_id(item), item} end)
      |> Enum.reject(fn {target_id, _item} -> is_nil(target_id) end)

    target_ids = items_by_target |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

    if target_ids == [] do
      %{}
    else
      releases_with_vns =
        from(r in Kaguya.Releases.Release,
          left_join: vn in VisualNovel,
          on: vn.id == r.visual_novel_id,
          where: r.id in ^target_ids,
          select: {r, vn}
        )
        |> Repo.all()
        |> Map.new(fn {r, vn} -> {r.id, {r, vn}} end)

      Map.new(items_by_target, fn {target_id, item} ->
        ref =
          case Map.get(releases_with_vns, target_id) do
            nil -> nil
            {release, vn} -> build_release_ref("release", item.entity_id, release, vn)
          end

        {{"release", item.entity_id}, ref}
      end)
      |> Map.reject(fn {_, v} -> is_nil(v) end)
    end
  end

  # `target_entity_id` lives in metadata for revision activities; we accept
  # both atom and string keys since the column round-trips through JSON.
  defp target_entity_id(%{metadata: %{} = meta}) do
    Map.get(meta, "target_entity_id") || Map.get(meta, :target_entity_id)
  end

  defp target_entity_id(_), do: nil

  defp build_vn_ref(entity_type, entity_id, vn) do
    %{
      entity_type: entity_type,
      entity_id: entity_id,
      name: vn.title,
      slug: vn.slug,
      image_url: Kaguya.VisualNovels.build_image_urls(vn)[:small],
      is_hidden: not is_nil(vn.hidden_at),
      parent_vn_slug: nil
    }
  end

  defp build_character_ref(entity_type, entity_id, character) do
    %{
      entity_type: entity_type,
      entity_id: entity_id,
      name: character.name,
      slug: character.slug,
      # Character image resolution requires preloading character_images +
      # picking the primary; defer to the frontend (which already has cached
      # CharacterFields data for any character it has rendered).
      image_url: nil,
      is_hidden: not is_nil(character.hidden_at),
      parent_vn_slug: nil
    }
  end

  defp build_producer_ref(entity_type, entity_id, producer) do
    %{
      entity_type: entity_type,
      entity_id: entity_id,
      name: producer.name,
      slug: producer.slug,
      image_url: nil,
      is_hidden: not is_nil(producer.hidden_at),
      parent_vn_slug: nil
    }
  end

  defp build_release_ref(entity_type, entity_id, release, parent_vn) do
    %{
      entity_type: entity_type,
      entity_id: entity_id,
      name: release.title,
      # Releases have no standalone page; navigation goes through the parent VN.
      slug: nil,
      image_url: parent_vn && Kaguya.VisualNovels.build_image_urls(parent_vn)[:small],
      is_hidden: not is_nil(release.hidden_at),
      parent_vn_slug: parent_vn && parent_vn.slug
    }
  end

  defp build_series_ref(entity_type, entity_id, series) do
    %{
      entity_type: entity_type,
      entity_id: entity_id,
      name: series.name,
      slug: series.slug,
      image_url: nil,
      is_hidden: not is_nil(series.hidden_at),
      parent_vn_slug: nil
    }
  end

  defp attach_entity_ref(%{entity_type: et, entity_id: id} = activity, refs) do
    %{activity | entity_ref: Map.get(refs, {et, id})}
  end

  # :reviewed and :liked_review — entity_id IS the review ID
  defp review_id_for(%{action: action, entity_id: id})
       when action in [:reviewed, :liked_review],
       do: [id]

  # :commented on a review — review ID is in metadata
  defp review_id_for(%{action: :commented, entity_type: "review_comment", metadata: meta}) do
    case meta do
      %{"parent_entity_id" => id} when is_binary(id) -> [id]
      %{parent_entity_id: id} when is_binary(id) -> [id]
      _ -> []
    end
  end

  defp review_id_for(_), do: []

  defp attach_review(%{action: action, entity_id: id} = activity, map)
       when action in [:reviewed, :liked_review] do
    %{activity | review: Map.get(map, id)}
  end

  defp attach_review(
         %{action: :commented, entity_type: "review_comment", metadata: meta} = activity,
         map
       ) do
    review_id =
      case meta do
        %{"parent_entity_id" => id} -> id
        %{parent_entity_id: id} -> id
        _ -> nil
      end

    %{activity | review: Map.get(map, review_id)}
  end

  defp attach_review(activity, _map), do: activity

  defp attach_list(%{action: action, entity_id: id} = activity, map)
       when action in [:created_list, :liked_list] do
    %{activity | list: Map.get(map, id)}
  end

  defp attach_list(activity, _map), do: activity

  defp attach_followed_user(
         %{action: :followed, entity_type: "user", entity_id: id} = activity,
         map
       ) do
    %{activity | followed_user: Map.get(map, id)}
  end

  defp attach_followed_user(activity, _map), do: activity

  defp attach_followed_producer(
         %{action: :followed, entity_type: "producer", entity_id: id} = activity,
         map
       ) do
    %{activity | followed_producer: Map.get(map, id)}
  end

  defp attach_followed_producer(activity, _map), do: activity

  defp attach_actor(%{user_id: uid} = activity, map) do
    %{activity | actor: Map.get(map, uid)}
  end

  defp batch_load(_schema, []), do: %{}

  defp batch_load(schema, ids) do
    from(r in schema, where: r.id in ^ids)
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end

  defp format_response({items, next_cursor, has_next}) do
    {:ok, %{items: items, next_cursor: next_cursor, has_next: has_next}}
  end
end
