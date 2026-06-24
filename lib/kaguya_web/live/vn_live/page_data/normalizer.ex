defmodule KaguyaWeb.VNLive.PageData.Normalizer do
  @moduledoc false
  # Pure (no-DB) shape helpers extracted from `KaguyaWeb.VNLive.PageData`.
  #
  # Each function takes a domain struct or value already loaded by the
  # parent module and returns a render-ready map. No queries here —
  # anything that needs DB access stays in `PageData` so the read
  # orchestration and the shape mapping live in different files.

  alias Kaguya.{Users, VisualNovels}

  # ---- Reviews ----

  def normalize_reviews(%{items: items, pagination: pagination}) do
    %{items: Enum.map(items, &normalize_review/1), pagination: pagination}
  end

  def normalize_review(review) do
    %{
      id: review.id,
      content: review.content || "",
      rating: review.rating,
      is_spoiler: review.is_spoiler,
      likes_count: review.likes_count || 0,
      comments_count: review.comments_count || 0,
      liked_by_me: false,
      inserted_at: review.inserted_at && NaiveDateTime.to_iso8601(review.inserted_at),
      user: normalize_user(review.user)
    }
  end

  def normalize_my_review({:ok, nil}), do: nil

  def normalize_my_review({:ok, review}),
    do: %{
      id: review.id,
      content: review.content || "",
      is_spoiler: review.is_spoiler,
      inserted_at: review.inserted_at
    }

  def normalize_my_review(_), do: nil

  # ---- Discussions ----

  def normalize_discussions(posts),
    do:
      Enum.map(posts, fn p ->
        %{
          id: p.id,
          title: p.title,
          short_id: p.short_id,
          comments_count: p.comments_count || 0,
          likes_count: p.likes_count || 0,
          inserted_at: p.inserted_at && NaiveDateTime.to_iso8601(p.inserted_at),
          is_pinned: p.is_pinned,
          is_locked: p.is_locked,
          user: normalize_user(p.user)
        }
      end)

  # ---- Covers / Screenshots ----

  def normalize_cover(cover),
    do: %{
      id: cover.id,
      images: VisualNovels.build_image_urls(cover.id),
      language: cover.language,
      release_date: cover.release_date && Date.to_iso8601(cover.release_date),
      likes_count: cover.likes_count || 0,
      liked_by_me: Map.get(cover, :liked_by_me, false),
      is_image_nsfw: Map.get(cover, :is_image_nsfw, false),
      is_image_suggestive: Map.get(cover, :is_image_suggestive, false)
    }

  def normalize_screenshot(s),
    do: %{
      id: s.id,
      images: VisualNovels.build_screenshot_urls(s.id),
      likes_count: s.likes_count || 0,
      liked_by_me: Map.get(s, :liked_by_me, false),
      is_nsfw: Map.get(s, :is_nsfw, false),
      is_brutal: Map.get(s, :is_brutal, false)
    }

  # ---- Quotes ----

  def normalize_quote(q),
    do: %{
      id: q.id,
      quote: q.quote,
      likes_count: q.likes_count || 0,
      favorites_count: q.favorites_count || 0,
      score: q.score || 0,
      liked_by_me: Map.get(q, :liked_by_me, false),
      favorited_by_me: Map.get(q, :favorited_by_me, false),
      character:
        q.character && %{id: q.character.id, name: q.character.name, slug: q.character.slug}
    }

  # ---- Releases ----

  def normalize_release(r),
    do: %{
      id: r.id,
      title: r.display_title || r.title,
      latin_title: r.latin_title,
      release_date: r.release_date && Date.to_iso8601(r.release_date),
      release_type: r.release_type,
      patch: r.patch,
      platform_labels: Map.get(r, :platform_labels) || r.platforms || [],
      platforms: r.platforms || [],
      languages: r.languages || [],
      mtl_languages: r.mtl_languages || [],
      original_language: r.original_language,
      freeware: r.freeware,
      official: r.official,
      has_ero: r.has_ero,
      minage: r.minage,
      uncensored: r.uncensored,
      voiced: r.voiced,
      engine: r.engine,
      resolution: resolution_label(r),
      media: r.media || [],
      notes: r.notes,
      flags: release_flags(r),
      extlinks: Enum.map(r.extlinks || [], &%{site: &1.site, label: &1.label, url: &1.url})
    }

  def resolution_label(%{reso_x: x, reso_y: y}) when is_integer(x) and is_integer(y),
    do: "#{x}x#{y}"

  def resolution_label(_), do: nil

  def release_flags(release) do
    []
    |> maybe_flag(
      release.release_type && release.release_type != "complete",
      release.release_type
    )
    |> maybe_flag(release.patch && release.official == true, "official")
    |> maybe_flag(!release.patch && release.official == false, "unofficial")
    |> maybe_flag(release.patch && release.freeware == false, "paid")
    |> maybe_flag(!release.patch && release.freeware == true, "free")
    |> maybe_flag(age_flag(release.minage) == "18+", "18+")
    |> maybe_flag(release.uncensored == true, "uncensored")
    |> maybe_flag(voiced_flag(release.voiced) != nil, voiced_flag(release.voiced))
    |> maybe_flag(resolution_label(release) != nil, resolution_label(release))
    |> Kernel.++(media_flags(release.media || []))
    |> Enum.reject(&is_nil/1)
  end

  defp maybe_flag(flags, true, flag), do: flags ++ [flag]
  defp maybe_flag(flags, _condition, _flag), do: flags

  defp age_flag(age) when is_integer(age) and age > 0, do: "#{age}+"
  defp age_flag(_), do: "All"

  defp voiced_flag(level) when level >= 4, do: "fully voiced"
  defp voiced_flag(level) when is_integer(level) and level > 0, do: "partly voiced"
  defp voiced_flag(_), do: nil

  defp media_flags(media) when is_list(media) do
    Enum.flat_map(media, fn
      %{"label" => "Internet download"} ->
        []

      %{label: "Internet download"} ->
        []

      %{"label" => label, "qty" => qty} when is_binary(label) and is_integer(qty) and qty > 1 ->
        ["#{qty}x #{label}"]

      %{label: label, qty: qty} when is_binary(label) and is_integer(qty) and qty > 1 ->
        ["#{qty}x #{label}"]

      %{"label" => label} when is_binary(label) ->
        [label]

      %{label: label} when is_binary(label) ->
        [label]

      _ ->
        []
    end)
  end

  defp media_flags(_), do: []

  # ---- Relations / Recommendations ----

  def normalize_relations(rows),
    do:
      Enum.map(
        rows,
        &%{
          relation_type: &1.relation_type,
          related_vn: normalize_cover_vn(&1.related_vn)
        }
      )

  def normalize_recommendations({:ok, rows}),
    do:
      Enum.map(
        rows,
        &%{
          net_votes: &1.net_votes,
          user_vote: Map.get(&1, :user_vote),
          visual_novel:
            &1.visual_novel
            |> normalize_cover_vn()
            |> Map.merge(%{
              average_rating: &1.visual_novel.average_rating,
              vndb_rating: &1.visual_novel.vndb_rating
            })
        }
      )

  def normalize_recommendations(_), do: []

  # ---- Lists ----

  def normalize_list(list, loaded_vns) do
    items =
      list
      |> list_items(loaded_vns)
      |> Enum.map(&normalize_list_item/1)

    %{
      id: list.id,
      slug: Map.get(list, :slug),
      name: list.name,
      description: list.description,
      likes_count: list.likes_count || 0,
      vns_count: list.vns_count || 0,
      user: normalize_user(list.user),
      visual_novels: items
    }
  end

  defp list_items(_list, %{items: items}) when is_list(items), do: items

  defp list_items(list, _loaded_vns) do
    case Map.get(list, :visual_novels) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      assoc when is_list(assoc) -> Enum.map(assoc, &%{position: nil, visual_novel: &1})
      assoc -> Map.get(assoc, :items, [])
    end
  end

  defp normalize_list_item(%{visual_novel: vn} = item) do
    %{
      position: Map.get(item, :position),
      visual_novel: normalize_cover_vn(vn)
    }
  end

  def normalize_cover_vn(vn) do
    %{
      id: vn.id,
      slug: vn.slug,
      title: vn.title,
      has_ero: vn.has_ero,
      images: VisualNovels.build_image_urls(vn),
      is_image_nsfw: vn.is_image_nsfw,
      is_image_suggestive: vn.is_image_suggestive
    }
  end

  # ---- Reading status / Shelves ----

  def normalize_reading_status(nil), do: nil

  def normalize_reading_status(status),
    do: %{
      id: status.id,
      status: status.status && status.status |> to_string() |> String.upcase(),
      date_started: status.date_started,
      date_finished: status.date_finished,
      note: status.note,
      library_added_at: status.library_added_at
    }

  def normalize_shelf(shelf), do: %{id: shelf.id, name: shelf.name, slug: shelf.slug}

  # ---- Producers ----

  def normalize_vn_producer(vp),
    do: %{role: vp.role, producer: normalize_userlike_producer(vp.producer)}

  defp normalize_userlike_producer(p), do: %{id: p.id, name: p.name, slug: p.slug}

  # ---- Tags ----

  def normalize_tag(tag) do
    kind =
      tag.tag.kind
      |> to_string()
      |> String.upcase()

    %{
      id: tag.tag.id,
      name: tag.tag.name,
      display_name: tag.tag.name,
      slug: tag.tag.slug,
      tag: %{
        id: tag.tag.id,
        name: tag.tag.name,
        display_name: tag.tag.name,
        slug: tag.tag.slug,
        kind: kind
      },
      kind: kind,
      spoiler_level: spoiler_level_string(tag.spoiler_level),
      relevance_score: tag.relevance_score,
      kaguya_vote_count: Map.get(tag, :kaguya_vote_count, 0),
      kaguya_bucket_counts: normalize_bucket_counts(Map.get(tag, :kaguya_bucket_counts)),
      my_vote: Map.get(tag, :my_vote)
    }
  end

  defp spoiler_level_string(nil), do: nil
  defp spoiler_level_string(level), do: level |> to_string() |> String.upcase()

  def normalize_bucket_counts(nil), do: [0, 0, 0, 0, 0, 0]

  def normalize_bucket_counts(counts) when is_list(counts) do
    0..5
    |> Enum.map(fn index ->
      counts
      |> Enum.at(index)
      |> case do
        count when is_integer(count) -> count
        _ -> 0
      end
    end)
  end

  def normalize_bucket_counts(_), do: [0, 0, 0, 0, 0, 0]

  # ---- Users ----

  def normalize_user(nil), do: %{id: nil, username: nil, display_name: nil, avatar_url: nil}

  def normalize_user(user),
    do: %{
      id: user.id,
      username: user.username,
      display_name: user.display_name,
      avatar_url: user.avatar_id && Users.build_avatar_urls(user.avatar_id).small
    }

  def normalize_users(users), do: Enum.map(users, &normalize_user/1)

  # ---- Search results ----

  def normalize_search_result(item) do
    %{
      id: Map.get(item, :id) || Map.get(item, "id"),
      slug: Map.get(item, :slug) || Map.get(item, "slug"),
      title: Map.get(item, :title) || Map.get(item, "title"),
      image_url: Map.get(item, :image_url) || Map.get(item, "image_url"),
      is_image_nsfw: Map.get(item, :is_image_nsfw) || Map.get(item, "is_image_nsfw") || false,
      is_image_suggestive:
        Map.get(item, :is_image_suggestive) || Map.get(item, "is_image_suggestive") || false,
      producers: Map.get(item, :producers) || Map.get(item, "producers") || []
    }
  end
end
