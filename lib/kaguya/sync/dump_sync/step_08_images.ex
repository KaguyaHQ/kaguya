defmodule Kaguya.Sync.DumpSync.Images do
  @moduledoc """
  Step 8: Full image lifecycle — cover selection, download, processing, and upload.

  Pipeline phases:
    08a. CoverSelection       — pick best cover per VN (needs vndb)
    08b. DownloadImages        — HTTP batch download from s.vndb.org
    08c. CoverProcessing       — 4 WebP variants, upload to R2
    08d. CharacterProcessing   — 1 WebP variant, upload to R2
    08e. ScreenshotProcessing  — 3 WebP variants, upload to R2, insert DB records
    08f. AltCoverProcessing    — alt cover selection, processing, upload, insert
    08g. FeaturedSelection     — violence-aware featured screenshot picker
  """

  require Logger

  alias Kaguya.Sync.DumpSync.Images.AltCoverProcessing
  alias Kaguya.Sync.DumpSync.Images.CharacterProcessing
  alias Kaguya.Sync.DumpSync.Images.CoverProcessing
  alias Kaguya.Sync.DumpSync.Images.CoverSelection
  alias Kaguya.Sync.DumpSync.Images.DownloadImages
  alias Kaguya.Sync.DumpSync.Images.FeaturedSelection
  alias Kaguya.Sync.DumpSync.Images.ImageMapping
  alias Kaguya.Sync.DumpSync.Images.ScreenshotProcessing
  alias Kaguya.Sync.DumpSync.Report

  def run(%{vndb: vndb, dry_run: dry_run, vn_mapping: vn_mapping} = ctx) do
    # Targeted import: scope to only target VNs
    vn_mapping =
      case ctx[:target_vndb_ids] do
        ids when is_list(ids) and ids != [] -> Map.take(vn_mapping, ids)
        _ -> vn_mapping
      end

    base_dir = Application.get_env(:kaguya, :vndb_image_dir, ".")

    Logger.info("Starting image processing step (base_dir: #{base_dir})...")

    ImageMapping.start()

    try do
      # Phase 1: Pick best cover + identify alt covers (both need vndb, independent queries)
      cover_task = Task.async(fn -> CoverSelection.run(vndb, vn_mapping) end)
      alt_cover_task = Task.async(fn -> AltCoverProcessing.identify_pending(vndb, vn_mapping) end)

      cover_selections = Task.await(cover_task, :infinity)
      {alt_pending, alt_cv_ids} = Task.await(alt_cover_task, :infinity)

      # Phase 2: Download covers/characters/alt covers while identifying pending screenshots
      # Downloads use HTTP (no vndb), identification uses vndb — independent resources
      {unique_screenshots, pending_sf_ids} =
        if dry_run do
          ScreenshotProcessing.identify_pending(vndb, vn_mapping)
        else
          id_task = Task.async(fn -> ScreenshotProcessing.identify_pending(vndb, vn_mapping) end)
          DownloadImages.download_covers(cover_selections, base_dir)
          DownloadImages.download_alt_covers(alt_cv_ids, base_dir)
          DownloadImages.download_characters(base_dir)
          Task.await(id_task, :infinity)
        end

      # Phase 3: Process covers + characters while screenshots download
      # Processing is CPU + R2 upload, downloading is HTTP — different bottlenecks
      cover_task =
        Task.async(fn -> CoverProcessing.run(cover_selections, vn_mapping, base_dir, dry_run) end)

      char_task = Task.async(fn -> CharacterProcessing.run(base_dir, dry_run) end)

      # If download raises, still await the tasks before re-raising so they
      # don't become orphaned and crash when ETS is cleaned up in the after block.
      download_error =
        if not dry_run do
          try do
            DownloadImages.download_screenshots(pending_sf_ids, base_dir)
            nil
          rescue
            e -> {e, __STACKTRACE__}
          end
        end

      # Await both tasks — if one raises, shut down the other to prevent
      # orphaned tasks that crash when the ETS table is cleaned up.
      {cover_count, cover_details, char_count, char_details} =
        try do
          {cc, cd} = Task.await(cover_task, :infinity)
          {chc, chd} = Task.await(char_task, :infinity)
          {cc, cd, chc, chd}
        rescue
          e ->
            Task.shutdown(cover_task, :brutal_kill)
            Task.shutdown(char_task, :brutal_kill)
            reraise e, __STACKTRACE__
        end

      case download_error do
        {e, stacktrace} -> reraise e, stacktrace
        _ -> :ok
      end

      # Phase 4: Process screenshots — resize, upload to R2, insert DB records
      {screenshot_count, screenshot_details} =
        ScreenshotProcessing.run(unique_screenshots, vn_mapping, base_dir, dry_run)

      # Phase 5: Process alt covers — resize, upload to R2, insert DB records
      {alt_cover_count, alt_cover_details} =
        AltCoverProcessing.run(alt_pending, vn_mapping, base_dir, dry_run)

      # Phase 6: Featured selection (needs vndb for violence check)
      featured_count = FeaturedSelection.run(vndb, dry_run)

      # Export full mapping with dimensions for cross-env use
      unless dry_run, do: ImageMapping.export()

      Report.record(:cover_images, cover_count, 0, cover_details)
      Report.record(:alt_covers, alt_cover_count, 0, alt_cover_details)
      Report.record(:character_images, char_count, 0, char_details)
      Report.record(:screenshots, screenshot_count, 0, screenshot_details)
      Report.record(:featured_screenshots, featured_count, 0)

      Logger.info(
        "Image step complete: #{cover_count} covers, #{alt_cover_count} alt covers, " <>
          "#{char_count} characters, #{screenshot_count} screenshots, #{featured_count} featured"
      )

      {:ok,
       %{
         covers: cover_count,
         alt_covers: alt_cover_count,
         characters: char_count,
         screenshots: screenshot_count,
         featured: featured_count
       }}
    after
      ImageMapping.stop()
    end
  end
end
