defmodule Kaguya.Sync.DumpSync.Images.FeaturedSelection do
  @moduledoc """
  Selects a featured screenshot for each VN, excluding any screenshot flagged
  `is_nsfw` or `is_brutal`.

  For VNs with screenshots but no `featured_screenshot_id`:
  1. Select candidates: DISTINCT ON (visual_novel_id) where NOT is_nsfw AND NOT is_brutal,
     ordered by landscape → largest area → id.
  2. VNs with only NSFW/brutal screenshots get `featured_screenshot_id = NULL`.

  Previously this step loaded violent sf_ids from the VNDB dump to exclude them.
  Since `vn_screenshots.is_nsfw` and `.is_brutal` are now populated at upload time
  from VNDB severity data, filtering by column is both simpler and more accurate
  (catches sexual-but-non-violent content the old filter missed).
  """

  require Logger

  import Ecto.Query

  alias Kaguya.Repo

  def run(_vndb, dry_run) do
    pending_count =
      from(vn in Kaguya.VisualNovels.VisualNovel,
        join: s in Kaguya.Screenshots.Screenshot,
        on: s.visual_novel_id == vn.id,
        where: is_nil(vn.featured_screenshot_id),
        select: count(vn.id, :distinct)
      )
      |> Repo.one()

    Logger.info("FeaturedSelection: #{pending_count} VNs need featured screenshots")

    if dry_run or pending_count == 0 do
      pending_count
    else
      count = set_featured_safe()
      Logger.info("FeaturedSelection: set featured for #{count} VNs")
      count
    end
  end

  # Raw SQL: DISTINCT ON + UPDATE...FROM subquery + computed ORDER BY
  # expressions have no Ecto DSL equivalent.
  defp set_featured_safe do
    %{num_rows: count} =
      Repo.query!("""
        UPDATE visual_novels vn
        SET featured_screenshot_id = sub.id,
            updated_at = NOW()
        FROM (
          SELECT DISTINCT ON (visual_novel_id) id, visual_novel_id
          FROM vn_screenshots
          WHERE NOT is_nsfw AND NOT is_brutal
          ORDER BY visual_novel_id, (width > height) DESC, (width * height) DESC, id
        ) sub
        WHERE sub.visual_novel_id = vn.id
          AND vn.featured_screenshot_id IS NULL
      """)

    count
  end
end
