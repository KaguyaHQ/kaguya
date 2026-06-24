defmodule Kaguya.Screenshots do
  @moduledoc """
  Context for VN screenshot likes and queries.
  """

  import Ecto.Query

  alias Kaguya.Repo
  alias Kaguya.VisualNovels.VisualNovel
  alias Kaguya.Screenshots.{Screenshot, ScreenshotLike}
  alias Kaguya.Activities
  alias Kaguya.Cdn

  @doc """
  Like a screenshot. Idempotent — re-liking is a no-op.
  """
  def like_screenshot(screenshot_id, user_id) do
    result =
      Repo.transact(fn ->
        case Repo.get(Screenshot, screenshot_id) do
          nil ->
            {:error, "Screenshot not found"}

          screenshot ->
            now = DateTime.utc_now() |> DateTime.truncate(:second)

            {count, _} =
              Repo.insert_all(
                ScreenshotLike,
                [%{user_id: user_id, vn_screenshot_id: screenshot_id, inserted_at: now}],
                on_conflict: :nothing,
                conflict_target: [:user_id, :vn_screenshot_id]
              )

            if count > 0 do
              increment_likes_count(screenshot_id)
              featured_changed = maybe_update_featured_screenshot(screenshot.visual_novel_id)
              {:ok, {screenshot, featured_changed}}
            else
              {:ok, :already_liked}
            end
        end
      end)

    with {:ok, {%Screenshot{} = screenshot, featured_changed}} <- result do
      record_liked_screenshot_activity(user_id, screenshot)
      if featured_changed, do: purge_vn_cdn(screenshot.visual_novel_id)
      {:ok, true}
    else
      {:ok, :already_liked} -> {:ok, true}
      other -> other
    end
  end

  @doc """
  Unlike a screenshot. Idempotent — unliking when not liked is a no-op.
  """
  def unlike_screenshot(screenshot_id, user_id) do
    result =
      Repo.transact(fn ->
        case Repo.get_by(ScreenshotLike, user_id: user_id, vn_screenshot_id: screenshot_id) do
          nil ->
            {:ok, :not_liked}

          like ->
            Repo.delete!(like)
            decrement_likes_count(screenshot_id)

            vn_id =
              Repo.one!(
                from s in Screenshot, where: s.id == ^screenshot_id, select: s.visual_novel_id
              )

            featured_changed = maybe_update_featured_screenshot(vn_id)
            {:ok, {:unliked, vn_id, featured_changed}}
        end
      end)

    with {:ok, {:unliked, vn_id, featured_changed}} <- result do
      Activities.delete_activity(user_id, :liked_screenshot, "screenshot", screenshot_id)
      if featured_changed, do: purge_vn_cdn(vn_id)
      {:ok, true}
    else
      {:ok, :not_liked} -> {:ok, true}
      other -> other
    end
  end

  @doc """
  List screenshots for a VN, ordered by likes_count desc then id.
  Optionally resolves `liked_by_me` for the given user.
  """
  def list_screenshots_for_vn(vn_id, user_id \\ nil) do
    query =
      from s in Screenshot,
        where: s.visual_novel_id == ^vn_id,
        order_by: [desc: s.likes_count, asc: s.id]

    query =
      if user_id do
        from s in query,
          left_join: l in ScreenshotLike,
          on: l.vn_screenshot_id == s.id and l.user_id == ^user_id,
          select_merge: %{liked_by_me: not is_nil(l.user_id)}
      else
        from s in query,
          select_merge: %{liked_by_me: false}
      end

    {:ok, Repo.all(query)}
  end

  @doc """
  Batched variant of `list_screenshots_for_vn/2`. Returns
  `%{vn_id => [screenshots]}`, one round-trip regardless of how many
  VNs are requested. Every requested `vn_id` is present (empty list
  if the VN has no screenshots), so callers can skip nil checks.
  """
  def list_screenshots_for_vns(_user_id, []), do: %{}

  def list_screenshots_for_vns(user_id, vn_ids) when is_list(vn_ids) do
    base =
      from s in Screenshot,
        where: s.visual_novel_id in ^vn_ids,
        order_by: [desc: s.likes_count, asc: s.id]

    query =
      if user_id do
        from s in base,
          left_join: l in ScreenshotLike,
          on: l.vn_screenshot_id == s.id and l.user_id == ^user_id,
          select_merge: %{liked_by_me: not is_nil(l.user_id)}
      else
        from s in base,
          select_merge: %{liked_by_me: false}
      end

    by_vn =
      query
      |> Repo.all()
      |> Enum.group_by(& &1.visual_novel_id)

    Enum.reduce(vn_ids, by_vn, fn vn_id, acc -> Map.put_new(acc, vn_id, []) end)
  end

  defp record_liked_screenshot_activity(user_id, %Screenshot{} = screenshot) do
    screenshot = Repo.preload(screenshot, :visual_novel)
    vn = screenshot.visual_novel
    screenshot_urls = Kaguya.VisualNovels.build_screenshot_urls(screenshot.id)

    # Moderation flags carry over into activity metadata so the feed UI can
    # respect viewer preferences (show/hide NSFW/brutal thumbnails). Older
    # records without these fields are always Safe+Tame by the pre-WD14
    # sync filter, so undefined safely reads as "show".
    metadata =
      if vn do
        %{
          screenshot_id: screenshot.id,
          screenshot_url: screenshot_urls[:small],
          screenshot_is_nsfw: screenshot.is_nsfw,
          screenshot_is_brutal: screenshot.is_brutal,
          vn_id: vn.id,
          vn_title: vn.title,
          vn_slug: vn.slug,
          vn_image_url: Kaguya.VisualNovels.build_image_urls(vn)[:small],
          vn_release_year: vn.release_date && vn.release_date.year
        }
      else
        %{
          screenshot_id: screenshot.id,
          screenshot_url: screenshot_urls[:small],
          screenshot_is_nsfw: screenshot.is_nsfw,
          screenshot_is_brutal: screenshot.is_brutal
        }
      end

    Activities.record_activity(%{
      user_id: user_id,
      action: :liked_screenshot,
      entity_type: "screenshot",
      entity_id: screenshot.id,
      metadata: metadata
    })
  end

  @doc """
  Upload a user-submitted screenshot for a VN.

  1. Insert a vn_screenshots row using upload_id as the screenshot ID.
     width/height are left nil at this point — the worker fills them in
     once it has decoded the source image.
  2. Enqueue ImageVariantWorker to generate resized variants and backfill
     dimensions in the background.

  The mutation returns as soon as the row exists (~10ms — no S3 traffic
  in the request path). Variants land on S3 within ~1s via the worker.
  The screenshot isn't attached to a revision yet — use submitVnEdit for
  that.

  NOTE: the per-VN screenshot count limit is no longer enforced here.
  The frontend's count check (in VnEditScreenshotsSection) is the single
  source of truth for normal users. Enforcing here at upload time would
  race with pending local removals — the user might have X'd a few
  existing screenshots in the edit form (which only get applied during
  submit_vn_edit, in Phase C), but this attach runs in Phase B before
  Phase C, so it would see the old DB count and falsely reject. API
  consumers bypassing the frontend can technically exceed the limit;
  that's a moderation concern, not a correctness one.
  """
  def upload_screenshot(visual_novel_id, upload_id, user_id) do
    with {:ok, vn} <- fetch_vn(visual_novel_id) do
      changeset =
        Screenshot.changeset(%Screenshot{}, %{
          id: upload_id,
          visual_novel_id: vn.id,
          uploaded_by: user_id,
          s3_key: "visual_novels/screenshots/#{upload_id}"
        })

      multi_result =
        Ecto.Multi.new()
        |> Ecto.Multi.insert(:screenshot, changeset)
        |> Oban.insert(:job, fn %{screenshot: ss} ->
          Kaguya.Uploads.ImageVariantWorker.new(%{
            type: "vn_screenshot",
            id: ss.id,
            vn_id: vn.id
          })
        end)
        |> Repo.transaction()

      case multi_result do
        {:ok, %{screenshot: ss}} -> {:ok, ss}
        {:error, _step, reason, _changes} -> {:error, reason}
      end
    end
  end

  @doc """
  Backfill width/height on a vn_screenshots row after the worker has
  decoded the source image. Public so ImageVariantWorker can call it
  from outside the Screenshots context.
  """
  def update_dimensions(screenshot_id, width, height) do
    from(s in Screenshot, where: s.id == ^screenshot_id)
    |> Repo.update_all(set: [width: width, height: height])

    :ok
  end

  defp fetch_vn(id) do
    case Repo.get(VisualNovel, id) do
      nil -> {:error, "Visual novel not found"}
      vn -> {:ok, vn}
    end
  end

  defp increment_likes_count(screenshot_id) do
    from(s in Screenshot, where: s.id == ^screenshot_id)
    |> Repo.update_all(inc: [likes_count: 1])
  end

  defp decrement_likes_count(screenshot_id) do
    from(s in Screenshot,
      where: s.id == ^screenshot_id and s.likes_count > 0
    )
    |> Repo.update_all(inc: [likes_count: -1])
  end

  defp maybe_update_featured_screenshot(visual_novel_id) do
    # Only clean screenshots are eligible as featured. Same filter as the
    # dump-sync initial selection (step_08g_featured_selection).
    most_liked_id =
      from(s in Screenshot,
        where:
          s.visual_novel_id == ^visual_novel_id and
            s.likes_count > 0 and
            not s.is_nsfw and
            not s.is_brutal,
        order_by: [
          desc: s.likes_count,
          desc: fragment("(? > ?)", s.width, s.height),
          desc: fragment("(? * ?)", s.width, s.height),
          asc: s.id
        ],
        limit: 1,
        select: s.id
      )
      |> Repo.one()

    if most_liked_id do
      {_, updated} =
        from(vn in VisualNovel,
          where:
            vn.id == ^visual_novel_id and
              (is_nil(vn.featured_screenshot_id) or
                 vn.featured_screenshot_id != ^most_liked_id),
          select: vn.id
        )
        |> Repo.update_all(set: [featured_screenshot_id: most_liked_id])

      updated != []
    else
      false
    end
  end

  defp purge_vn_cdn(vn_id) do
    slug = Repo.one(from v in VisualNovel, where: v.id == ^vn_id, select: v.slug)
    if slug, do: Cdn.purge_vn_cache(slug)
  end
end
