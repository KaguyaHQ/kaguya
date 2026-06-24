defmodule KaguyaWeb.ProfileLive.StatsData do
  @moduledoc """
  View-model assembly for the `/@:username/stats` LiveView.

  Keeps the stats page LiveView focused on routing and composition while this
  module owns context calls, lightweight query decoration, and render-ready
  stats maps.
  """

  import Ecto.Query

  alias Kaguya.{Library, Lists, Producers, Repo, Stats, Tags, VisualNovels}
  alias Kaguya.Reviews.Rating
  alias Kaguya.VisualNovels.{TitleCategory, VisualNovel}
  alias KaguyaWeb.Components.Profile.Stats.Charting

  @length_buckets [
    {"very_short", "<2 hours", "<2h"},
    {"short", "2-10 hours", "2-10h"},
    {"medium", "10-30 hours", "10-30h"},
    {"long", "30-50 hours", "30-50h"},
    {"very_long", "50+ hours", "50h+"}
  ]

  @age_buckets [
    {"all_ages", "All Ages"},
    {"13+", "13+"},
    {"16+", "16+"},
    {"18+", "18+"}
  ]

  def load_stats(user, profile, viewer) do
    allowed = TitleCategory.allowed_categories(viewer || %{})
    snapshot = Stats.build_user_vn_stats(user, nil, allowed_categories: allowed)
    hero = Map.fetch!(snapshot, :hero_stats)

    length_dist =
      Library.library_length_dist(user.id, %{status: :read}, allowed_categories: allowed)

    age_dist =
      Library.library_age_rating_dist(user.id, %{status: :read}, allowed_categories: allowed)

    most_read_tags = tags_from_stats(Map.get(snapshot, :most_read_vn_tags, []), :count)
    highest_rated_tags = tags_from_stats(Map.get(snapshot, :highest_rated_vn_tags, []), :rating)

    most_read_producers =
      producers_from_stats(Map.get(snapshot, :most_read_producers, []), :count)

    highest_rated_producers =
      producers_from_stats(Map.get(snapshot, :highest_rated_producers, []), :rating)

    language_items = language_items(Map.get(snapshot, :most_read_languages, []))
    age_items = bucket_items(age_dist, @age_buckets)

    curated_progress =
      user.id
      |> Lists.curated_list_progress(allowed_categories: allowed)
      |> Enum.filter(fn item -> progress_total(item) > 0 end)
      |> Enum.map(&decorate_progress_item/1)

    stats = %{
      hero: %{
        vns_count: hero.vns_count || 0,
        reviews_count: hero.reviews_count || 0,
        lists_count: hero.lists_count || 0,
        read_time_minutes: hero.read_time_minutes || 0,
        producers_count: hero.producers_count || 0
      },
      hero_covers: hero_covers(user.id, allowed),
      updated_at: Map.get(snapshot, :updated_at),
      avatar_url: profile.avatar_urls[:medium] || profile.avatar_urls[:small],
      release_year_chart:
        Charting.build_year_chart(
          Map.get(snapshot, :vns_by_release_year_hist),
          Map.get(snapshot, :read_time_by_release_year_hist),
          Map.get(snapshot, :mean_score_by_release_year_hist),
          "releaseYear"
        ),
      read_year_chart:
        Charting.build_year_chart(
          Map.get(snapshot, :vns_hist),
          Map.get(snapshot, :read_time_hist),
          Map.get(snapshot, :mean_score_hist),
          "readYear"
        ),
      length_items: length_items(length_dist),
      age_items: age_items,
      language_items: language_items,
      most_read_tags: most_read_tags,
      highest_rated_tags: highest_rated_tags,
      most_read_producers: most_read_producers,
      highest_rated_producers: highest_rated_producers,
      curated_progress: curated_progress,
      most_liked_review: decorate_review(Map.get(snapshot, :most_liked_vn_review)),
      most_liked_list: decorate_list(Map.get(snapshot, :most_liked_vn_list))
    }

    Map.put(stats, :has_content?, stats_has_content?(stats, profile))
  end

  defp stats_has_content?(stats, profile) do
    profile.ratings_count > 0 or
      stats.release_year_chart.has_data? or
      stats.read_year_chart.has_data? or
      stats.length_items != [] or
      stats.age_items != [] or
      stats.language_items != [] or
      stats.most_read_tags != [] or
      stats.highest_rated_tags != [] or
      stats.most_read_producers != [] or
      stats.highest_rated_producers != [] or
      stats.curated_progress != [] or
      not is_nil(stats.most_liked_review) or
      not is_nil(stats.most_liked_list)
  end

  # Highest-rated VNs the user has scored, used as a blurred ambient backdrop
  # behind the stats hero. SFW covers only (the image flags, not VN content),
  # since the wall renders regardless of viewer NSFW preferences.
  defp hero_covers(user_id, allowed) do
    base =
      from r in Rating,
        join: vn in VisualNovel,
        on: vn.id == r.visual_novel_id,
        where: r.user_id == ^user_id,
        where: not is_nil(vn.primary_image_id),
        where: not coalesce(vn.is_image_nsfw, false),
        where: not coalesce(vn.is_image_suggestive, false),
        order_by: [desc: r.rating, desc: r.visual_novel_id],
        limit: 30,
        select: %{
          primary_image_id: vn.primary_image_id,
          temp_image_url: vn.temp_image_url,
          title: vn.title
        }

    base =
      if is_nil(allowed), do: base, else: where(base, [_r, vn], vn.title_category in ^allowed)

    base
    |> Repo.all()
    |> Enum.map(fn vn ->
      images = VisualNovels.build_image_urls(vn)
      %{src: images[:medium] || images[:large], title: vn.title}
    end)
    |> Enum.reject(&is_nil(&1.src))
  end

  defp tags_from_stats(stats, value_kind) do
    tag_ids = stats |> Enum.map(& &1.tag_id) |> Enum.reject(&is_nil/1)
    tags = Repo.all(from t in Tags.Tag, where: t.id in ^tag_ids) |> Map.new(&{&1.id, &1})

    stats
    |> Enum.map(fn stat ->
      tag = Map.get(tags, stat.tag_id)

      %{
        name: tag && tag.name,
        slug: tag && tag.slug,
        count: Map.get(stat, :count) || 0,
        rating: Map.get(stat, :avg_user_rating) || 0.0
      }
    end)
    |> Enum.reject(&(is_nil(&1.name) or &1.name == ""))
    |> sort_stat_items(value_kind)
    |> Enum.take(10)
  end

  defp producers_from_stats(stats, value_kind) do
    producer_ids = stats |> Enum.map(& &1.producer_id) |> Enum.reject(&is_nil/1)

    producers =
      Repo.all(from p in Producers.Producer, where: p.id in ^producer_ids)
      |> Map.new(&{&1.id, &1})

    stats
    |> Enum.map(fn stat ->
      producer = Map.get(producers, stat.producer_id)

      %{
        name: producer && producer.name,
        slug: producer && producer.slug,
        count: Map.get(stat, :count) || 0,
        rating: Map.get(stat, :avg_user_rating) || 0.0
      }
    end)
    |> Enum.reject(&(is_nil(&1.name) or &1.name == ""))
    |> sort_stat_items(value_kind)
  end

  defp sort_stat_items(items, :count), do: Enum.sort_by(items, & &1.count, :desc)
  defp sort_stat_items(items, :rating), do: Enum.sort_by(items, & &1.rating, :desc)

  defp length_items(dist) do
    @length_buckets
    |> Enum.map(fn {key, label, short_label} ->
      %{key: key, label: label, short_label: short_label, value: Map.get(dist || %{}, key, 0)}
    end)
    |> Enum.reject(&(&1.value == 0))
  end

  defp bucket_items(dist, buckets) do
    buckets
    |> Enum.map(fn {key, label} ->
      %{key: key, label: label, value: Map.get(dist || %{}, key, 0)}
    end)
    |> Enum.reject(&(&1.value == 0))
  end

  defp language_items(rows) do
    rows
    |> Enum.map(fn row ->
      language = Map.get(row, :language) || Map.get(row, "language")
      count = Map.get(row, :count) || Map.get(row, "count") || 0

      %{key: language, label: language_name(language), value: count}
    end)
    |> Enum.reject(&(is_nil(&1.key) or &1.value == 0))
    |> Enum.sort_by(& &1.value, :desc)
    |> Enum.take(10)
  end

  defp decorate_review(nil), do: nil

  defp decorate_review(review) do
    review = Repo.preload(review, :visual_novel)

    rating =
      Repo.one(
        from r in Rating,
          where: r.user_id == ^review.user_id and r.visual_novel_id == ^review.visual_novel_id,
          select: r.rating
      )

    %{
      content: review.content,
      likes_count: review.likes_count || 0,
      rating: rating,
      visual_novel: decorate_vn(review.visual_novel)
    }
  end

  defp decorate_list(nil), do: nil

  defp decorate_list(list) do
    list = Repo.preload(list, :user)
    covers = list_covers(list.id)

    %{
      name: list.name,
      slug: list.slug,
      description: list.description,
      likes_count: list.likes_count || 0,
      vns_count: list.vns_count || length(covers),
      username: list.user && list.user.username,
      covers: covers
    }
  end

  defp list_covers(list_id) do
    from(li in Lists.ListItem,
      join: vn in assoc(li, :visual_novel),
      where: li.list_id == ^list_id,
      order_by: [asc: li.position],
      limit: 5,
      select: vn
    )
    |> Repo.all()
    |> Enum.map(&decorate_vn/1)
  end

  defp decorate_vn(nil), do: nil

  defp decorate_vn(vn) do
    %{
      id: vn.id,
      title: vn.title,
      slug: vn.slug,
      images: VisualNovels.build_image_urls(vn),
      has_ero: vn.has_ero,
      is_image_nsfw: vn.is_image_nsfw,
      is_image_suggestive: vn.is_image_suggestive
    }
  end

  defp decorate_progress_item(%{list: list, read_count: read_count}) do
    %{
      id: list.id,
      name: list.name || "List",
      slug: list.slug,
      username: list_owner_username(list),
      read_count: read_count || 0,
      total: list.vns_count || 0
    }
  end

  defp progress_total(%{list: %{vns_count: count}}) when is_integer(count), do: count
  defp progress_total(_), do: 0

  defp list_owner_username(%{user: %{username: username}}) when is_binary(username), do: username

  defp list_owner_username(%{user_id: user_id}) when is_binary(user_id) do
    Repo.one(from u in Kaguya.Users.User, where: u.id == ^user_id, select: u.username)
  end

  defp list_owner_username(_), do: nil

  defp language_name(nil), do: ""
  defp language_name("en"), do: "English"
  defp language_name("ja"), do: "Japanese"
  defp language_name("ru"), do: "Russian"
  defp language_name("zh-Hans"), do: "Simplified Chinese"
  defp language_name("zh-Hant"), do: "Traditional Chinese"
  defp language_name("ko"), do: "Korean"
  defp language_name("es"), do: "Spanish"
  defp language_name("fr"), do: "French"
  defp language_name("de"), do: "German"
  defp language_name("pt-br"), do: "Portuguese (BR)"
  defp language_name(code) when is_binary(code), do: String.upcase(code)
end
