defmodule KaguyaWeb.ReviewLive.Data do
  @moduledoc """
  Pure data loader for `KaguyaWeb.ReviewLive.Show`.

  Pulls everything the show page needs in a single function call so the
  LiveView stays slim and the loading logic is easy to unit-test in
  isolation. Mirrors the structure of `KaguyaWeb.ListLive.Data` so the
  two LiveViews look and feel similar.

  Returned payload (on `{:ok, …}`):

      %{
        review:         %{...},  # normalized review (likes count, liked_by_me, rating, …)
        vn:             %{...},  # normalized VN (cover, has_ero, slug, title, featured_screenshot)
        owner:          %{...},  # author of the review (username, display_name, avatar_url)
        more_reviews:   [...],   # up to 5 other reviews by the same user (excluded current)
        is_mine:        boolean, # viewer authored this review
        can_moderate:   boolean, # mod_reviews / admin
        is_hidden:      boolean, # hidden_at != nil
        is_locked:      boolean, # locked
        liked_by_me:    boolean  # viewer liked the review
      }

  Returns `{:error, :not_found}` if either the author, the VN, or the
  review row is missing.
  """

  alias Kaguya.Reviews
  alias Kaguya.Reviews.{Rating, Review}
  alias Kaguya.Repo
  alias Kaguya.Users
  alias Kaguya.VisualNovels

  @more_reviews_limit 6
  @rating_precision 2

  @doc """
  Loads everything the single-review page needs.
  """
  def load_show_page(username, vn_slug, opts \\ [])
      when is_binary(username) and is_binary(vn_slug) do
    viewer = Keyword.get(opts, :viewer)
    viewer_id = user_id(viewer)
    viewer_perms = viewer_perms(viewer)

    with {:ok, owner} <- Users.get_user_by_username(username),
         {:ok, vn} <- fetch_vn(vn_slug),
         {:ok, review} <- fetch_review(vn.id, owner.id, viewer_id, viewer_perms) do
      review = Repo.preload(review, [])
      liked_by_me = liked_by_me?(review.id, viewer_id)
      rating_value = fetch_rating(owner.id, vn.id)

      {:ok,
       %{
         review: normalize_review(review, rating_value, liked_by_me),
         vn: normalize_vn(vn),
         owner: normalize_user(owner),
         more_reviews: more_reviews(owner.id, review.id, viewer_id),
         is_mine: not is_nil(viewer_id) and viewer_id == owner.id,
         can_moderate: moderator?(viewer_perms),
         is_hidden: not is_nil(review.hidden_at),
         is_locked: !!review.is_locked,
         liked_by_me: liked_by_me
       }}
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp fetch_vn(slug) do
    case VisualNovels.get_visual_novel_by_slug(slug) do
      nil -> {:error, :not_found}
      vn -> {:ok, vn}
    end
  end

  defp fetch_review(vn_id, owner_id, viewer_id, viewer_perms) do
    case Repo.get_by(Review, visual_novel_id: vn_id, user_id: owner_id) do
      nil ->
        {:error, :not_found}

      %Review{hidden_at: nil} = review ->
        {:ok, review}

      %Review{} = review ->
        # Hidden reviews are only visible to the author or to moderators —
        # everyone else gets the same 404 as Next.js `notFound()`.
        cond do
          viewer_id == review.user_id -> {:ok, review}
          moderator?(viewer_perms) -> {:ok, review}
          true -> {:error, :not_found}
        end
    end
  end

  defp liked_by_me?(_review_id, nil), do: false

  defp liked_by_me?(review_id, user_id) do
    case Reviews.liked_review?(review_id, user_id) do
      {:ok, liked?} -> liked?
      liked? when is_boolean(liked?) -> liked?
      _ -> false
    end
  end

  defp fetch_rating(user_id, vn_id) do
    case Repo.get_by(Rating, user_id: user_id, visual_novel_id: vn_id) do
      %Rating{rating: r} when is_number(r) -> r
      _ -> nil
    end
  end

  defp more_reviews(owner_id, current_review_id, viewer_id) do
    {:ok, %{items: items}} =
      Reviews.list_reviews_for_user(
        owner_id,
        %{page: 1, page_size: @more_reviews_limit, sort_by: :newest, skip_count: true},
        viewer_id
      )

    items =
      items
      |> Enum.reject(fn r -> r.id == current_review_id end)
      |> Enum.take(5)
      |> Repo.preload(:visual_novel)

    Enum.map(items, fn r ->
      %{
        id: r.id,
        rating: rating_or_nil(r.rating),
        visual_novel: normalize_vn(r.visual_novel)
      }
    end)
  end

  defp normalize_review(%Review{} = review, rating_value, liked_by_me) do
    %{
      id: review.id,
      content: review.content,
      rating: rating_or_nil(rating_value),
      is_spoiler: review.is_spoiler,
      is_edited: review.is_edited,
      is_locked: review.is_locked,
      is_hidden: not is_nil(review.hidden_at),
      hidden_at: review.hidden_at,
      likes_count: review.likes_count || 0,
      comments_count: review.comments_count || 0,
      liked_by_me: liked_by_me,
      inserted_at: review.inserted_at,
      updated_at: review.updated_at,
      source: review.source,
      user_id: review.user_id,
      visual_novel_id: review.visual_novel_id
    }
  end

  defp normalize_vn(nil), do: nil

  defp normalize_vn(%Kaguya.VisualNovels.VisualNovel{} = vn) do
    images = VisualNovels.build_image_urls(vn)

    %{
      id: vn.id,
      slug: vn.slug,
      title: vn.title,
      has_ero: vn.has_ero,
      is_image_nsfw: vn.is_image_nsfw,
      is_image_suggestive: vn.is_image_suggestive,
      images: images,
      featured_screenshot:
        case vn.featured_screenshot_id do
          nil -> nil
          id -> VisualNovels.build_screenshot_urls(id)
        end
    }
  end

  defp normalize_vn(%{} = vn) do
    # Already partially normalized (e.g. from previews) — pass through unchanged.
    vn
  end

  defp normalize_user(nil), do: nil

  defp normalize_user(%Kaguya.Users.User{} = user) do
    avatar_urls = Users.build_avatar_urls(user.avatar_id)

    %{
      id: user.id,
      username: user.username,
      display_name: user.display_name || user.username,
      avatar_url: avatar_urls[:small],
      avatar_urls: avatar_urls
    }
  end

  defp rating_or_nil(nil), do: nil
  defp rating_or_nil(r) when is_number(r), do: Float.round(r * 1.0, @rating_precision)
  defp rating_or_nil(_), do: nil

  defp user_id(%{id: id}) when is_binary(id), do: id
  defp user_id(_), do: nil

  defp viewer_perms(nil), do: %{}

  defp viewer_perms(viewer) when is_map(viewer) do
    %{
      mod_reviews: Map.get(viewer, :mod_reviews, false),
      role: Map.get(viewer, :role)
    }
  end

  defp moderator?(%{mod_reviews: true}), do: true
  defp moderator?(%{role: :admin}), do: true
  defp moderator?(%{role: "admin"}), do: true
  defp moderator?(_), do: false
end
