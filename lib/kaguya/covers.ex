defmodule Kaguya.Covers do
  @moduledoc """
  Context for VN cover image likes and queries.
  """

  require Logger

  import Ecto.Query

  alias Kaguya.Repo
  alias Kaguya.VisualNovels.{Image, VisualNovel}
  alias Kaguya.Covers.ImageLike
  alias Kaguya.Activities
  alias Kaguya.Cdn
  alias Kaguya.SearchIndex

  @doc """
  Like a cover image. Idempotent — re-liking is a no-op.
  """
  def like_cover(vn_image_id, user_id) do
    result =
      Repo.transact(fn ->
        case Repo.get(Image, vn_image_id) do
          nil ->
            {:error, "Cover not found"}

          cover ->
            now = DateTime.utc_now() |> DateTime.truncate(:second)

            {count, _} =
              Repo.insert_all(
                ImageLike,
                [%{user_id: user_id, vn_image_id: vn_image_id, inserted_at: now}],
                on_conflict: :nothing,
                conflict_target: [:user_id, :vn_image_id]
              )

            if count > 0 do
              increment_likes_count(vn_image_id)
              changed = maybe_update_primary_image(cover.visual_novel_id)
              {:ok, {cover, changed}}
            else
              {:ok, :already_liked}
            end
        end
      end)

    with {:ok, {%Image{} = cover, changed?}} <- result do
      record_liked_cover_activity(user_id, cover)

      if changed? do
        reindex_vn(cover.visual_novel_id)
        purge_vn_cdn(cover.visual_novel_id)
      end

      {:ok, true}
    else
      {:ok, :already_liked} -> {:ok, true}
      other -> other
    end
  end

  @doc """
  Unlike a cover image. Idempotent — unliking when not liked is a no-op.
  """
  def unlike_cover(vn_image_id, user_id) do
    result =
      Repo.transact(fn ->
        case Repo.get_by(ImageLike, user_id: user_id, vn_image_id: vn_image_id) do
          nil ->
            {:ok, :not_liked}

          like ->
            Repo.delete!(like)
            decrement_likes_count(vn_image_id)

            vn_id =
              Repo.one!(from c in Image, where: c.id == ^vn_image_id, select: c.visual_novel_id)

            changed = maybe_update_primary_image(vn_id)
            {:ok, {:unliked, vn_id, changed}}
        end
      end)

    with {:ok, {:unliked, vn_id, changed?}} <- result do
      Activities.delete_activity(user_id, :liked_cover, "cover", vn_image_id)

      if changed? do
        reindex_vn(vn_id)
        purge_vn_cdn(vn_id)
      end

      {:ok, true}
    else
      {:ok, :not_liked} -> {:ok, true}
      other -> other
    end
  end

  @doc """
  List covers for a VN, ordered by vndb_votes desc, likes_count desc, then id.
  Optionally resolves `liked_by_me` for the given user.
  """
  def list_covers_for_vn(vn_id, user_id \\ nil) do
    query =
      from c in Image,
        where: c.visual_novel_id == ^vn_id,
        order_by: [desc: c.vndb_votes, desc: c.likes_count, asc: c.id]

    query =
      if user_id do
        from c in query,
          left_join: l in ImageLike,
          on: l.vn_image_id == c.id and l.user_id == ^user_id,
          select_merge: %{liked_by_me: not is_nil(l.user_id)}
      else
        from c in query,
          select_merge: %{liked_by_me: false}
      end

    {:ok, Repo.all(query)}
  end

  defp record_liked_cover_activity(user_id, %Image{} = cover) do
    cover = Repo.preload(cover, :visual_novel)
    vn = cover.visual_novel
    cover_urls = Kaguya.VisualNovels.build_image_urls(cover.id)

    metadata =
      if vn do
        %{
          cover_id: cover.id,
          cover_url: cover_urls[:small],
          vn_id: vn.id,
          vn_title: vn.title,
          vn_slug: vn.slug,
          vn_image_url: Kaguya.VisualNovels.build_image_urls(vn)[:small],
          vn_release_year: vn.release_date && vn.release_date.year
        }
      else
        %{cover_id: cover.id, cover_url: cover_urls[:small]}
      end

    Activities.record_activity(%{
      user_id: user_id,
      action: :liked_cover,
      entity_type: "cover",
      entity_id: cover.id,
      metadata: metadata
    })
  end

  defp increment_likes_count(vn_image_id) do
    from(c in Image, where: c.id == ^vn_image_id)
    |> Repo.update_all(inc: [likes_count: 1])
  end

  defp decrement_likes_count(vn_image_id) do
    from(c in Image,
      where: c.id == ^vn_image_id and c.likes_count > 0
    )
    |> Repo.update_all(inc: [likes_count: -1])
  end

  defp maybe_update_primary_image(visual_novel_id) do
    # Don't override a pinned cover
    vn = Repo.get!(VisualNovel, visual_novel_id)
    if vn.is_cover_pinned, do: false, else: do_update_primary_image(visual_novel_id)
  end

  defp do_update_primary_image(visual_novel_id) do
    most_liked =
      from(c in Image,
        where: c.visual_novel_id == ^visual_novel_id and c.likes_count > 0,
        order_by: [
          desc: c.likes_count,
          desc: c.vndb_votes,
          asc: c.id
        ],
        limit: 1,
        select: %{
          id: c.id,
          is_image_nsfw: c.is_image_nsfw,
          is_image_suggestive: c.is_image_suggestive
        }
      )
      |> Repo.one()

    if most_liked do
      {_, updated} =
        from(vn in VisualNovel,
          where:
            vn.id == ^visual_novel_id and
              (is_nil(vn.primary_image_id) or vn.primary_image_id != ^most_liked.id),
          select: vn.id
        )
        |> Repo.update_all(
          set: [
            primary_image_id: most_liked.id,
            is_image_nsfw: most_liked.is_image_nsfw,
            is_image_suggestive: most_liked.is_image_suggestive
          ]
        )

      updated != []
    else
      false
    end
  end

  @doc """
  Update cover metadata (NSFW flags, language, release_date).
  """
  def update_cover(vn_image_id, attrs) do
    case Repo.get(Image, vn_image_id) do
      nil ->
        {:error, "Cover not found"}

      cover ->
        cover
        |> Image.changeset(
          Map.take(attrs, [:is_image_nsfw, :is_image_suggestive, :language, :release_date])
        )
        |> Repo.update()
    end
  end

  @doc """
  Upload a user-submitted cover image for a VN.

  1. Insert a vn_images row using upload_id as the image ID (so S3 paths
     match URL generation). width/height are left nil at this point —
     the worker fills them in once it has decoded the source image.
  2. Enqueue ImageVariantWorker to generate resized variants and backfill
     dimensions in the background.
  3. Auto-set as primary if VN has no cover yet.

  The mutation returns as soon as the row exists (~10ms — no S3 traffic
  in the request path). Variants land on S3 within ~1-2s via the worker.
  URLs built from cover.id are valid immediately and resolve once the
  worker finishes.
  """
  def upload_cover(visual_novel_id, upload_id, user_id) do
    with {:ok, vn} <- fetch_vn(visual_novel_id) do
      changeset =
        Image.changeset(%Image{}, %{
          id: upload_id,
          visual_novel_id: vn.id,
          uploaded_by: user_id
        })

      # Atomic: row insert and worker enqueue commit (or fail) together.
      # Without this, an Oban.insert! that crashes after the row insert
      # would leave a permanent orphan cover with no pending variants job.
      multi_result =
        Ecto.Multi.new()
        |> Ecto.Multi.insert(:cover, changeset)
        |> Oban.insert(:job, fn %{cover: cover} ->
          Kaguya.Uploads.ImageVariantWorker.new(%{
            type: "vn_cover",
            id: cover.id,
            vn_id: vn.id
          })
        end)
        |> Repo.transaction()

      case multi_result do
        {:ok, %{cover: cover}} ->
          # Auto-set as primary if VN has no cover yet
          if is_nil(vn.primary_image_id), do: set_primary_cover(vn.id, cover.id)
          {:ok, cover}

        {:error, _step, reason, _changes} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Set a cover as primary. Does NOT pin — community likes can still override.
  """
  def set_primary_cover(visual_novel_id, vn_image_id) do
    case Repo.get(Image, vn_image_id) do
      nil ->
        {:error, "Cover not found"}

      %{visual_novel_id: ^visual_novel_id} = cover ->
        from(v in VisualNovel, where: v.id == ^visual_novel_id)
        |> Repo.update_all(
          set: [
            primary_image_id: cover.id,
            is_image_nsfw: cover.is_image_nsfw || false,
            is_image_suggestive: cover.is_image_suggestive || false
          ]
        )

        purge_vn_cdn(visual_novel_id)
        {:ok, true}

      _ ->
        {:error, "Cover does not belong to this visual novel"}
    end
  end

  @doc """
  Pin a specific cover as the primary image for a VN (mod/admin only).
  Overrides community voting until unpinned.
  """
  def pin_cover(visual_novel_id, vn_image_id) do
    case Repo.get(Image, vn_image_id) do
      nil ->
        {:error, "Cover not found"}

      %{visual_novel_id: ^visual_novel_id} = cover ->
        from(v in VisualNovel, where: v.id == ^visual_novel_id)
        |> Repo.update_all(
          set: [
            primary_image_id: cover.id,
            is_image_nsfw: cover.is_image_nsfw,
            is_image_suggestive: cover.is_image_suggestive,
            is_cover_pinned: true
          ]
        )

        reindex_vn(visual_novel_id)
        purge_vn_cdn(visual_novel_id)
        {:ok, true}

      _ ->
        {:error, "Cover does not belong to this visual novel"}
    end
  end

  @doc """
  Unpin the cover for a VN, reverting to community vote-based selection.
  """
  def unpin_cover(visual_novel_id) do
    from(v in VisualNovel, where: v.id == ^visual_novel_id)
    |> Repo.update_all(set: [is_cover_pinned: false])

    maybe_update_primary_image(visual_novel_id)
    reindex_vn(visual_novel_id)
    purge_vn_cdn(visual_novel_id)
    {:ok, true}
  end

  defp fetch_vn(id) do
    case Repo.get(VisualNovel, id) do
      nil -> {:error, "Visual novel not found"}
      vn -> {:ok, vn}
    end
  end

  @doc """
  Purge CDN cache for a VN's pages by slug. Public so background workers
  (e.g. ImageVariantWorker) can trigger a purge once new variants land.
  """
  def purge_vn_cdn(vn_id) do
    slug = Repo.one(from v in VisualNovel, where: v.id == ^vn_id, select: v.slug)
    if slug, do: Cdn.purge_vn_cache(slug)
  end

  @doc """
  Backfill width/height on a vn_images row after the worker has decoded
  the source image. Public so ImageVariantWorker can call it from outside
  the Covers context.
  """
  def update_dimensions(image_id, width, height) do
    from(i in Image, where: i.id == ^image_id)
    |> Repo.update_all(set: [width: width, height: height])

    :ok
  end

  defp reindex_vn(visual_novel_id) do
    vn =
      from(v in VisualNovel,
        where: v.id == ^visual_novel_id,
        preload: [:primary_image, :vn_titles, vn_producers: :producer]
      )
      |> Repo.one()

    if vn, do: SearchIndex.index_visual_novels(vn)
  rescue
    e ->
      Logger.warning(
        "[Covers] Meilisearch reindex failed for VN #{visual_novel_id}: #{Exception.message(e)}"
      )
  end
end
