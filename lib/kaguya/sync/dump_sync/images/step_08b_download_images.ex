defmodule Kaguya.Sync.DumpSync.Images.DownloadImages do
  @moduledoc """
  Downloads delta images from VNDB's image server (s.vndb.org) via HTTP.

  Three entry points — one per category — so the coordinator can
  schedule them independently for pipeline parallelism.

  Skipped when `SKIP_IMAGE_DOWNLOAD=true` env var is set.
  Non-fatal: if downloads fail, processing steps just skip missing files.
  """

  require Logger

  alias Kaguya.Sync.DumpSync.Images.ImagePath

  @vndb_image_base "https://s.vndb.org"
  @concurrency 10
  @timeout 30_000

  @doc "Download cover images identified by CoverSelection."
  def download_covers(cover_selections, base_dir) do
    if skip?() do
      Logger.info("Download: covers skipped (SKIP_IMAGE_DOWNLOAD=true)")
    else
      cv_ids =
        cover_selections
        |> Map.values()
        |> Enum.map(& &1.cv_id)
        |> Enum.uniq()
        |> Enum.filter(&String.starts_with?(&1, "cv"))

      to_download = reject_existing(cv_ids, base_dir)
      Logger.info("Download: #{length(to_download)}/#{length(cv_ids)} covers to download")
      download_batch(to_download, base_dir, "covers")
    end
  end

  @doc "Download alt cover images identified by AltCoverProcessing."
  def download_alt_covers(pending_cv_ids, base_dir) do
    if skip?() do
      Logger.info("Download: alt covers skipped (SKIP_IMAGE_DOWNLOAD=true)")
    else
      to_download = reject_existing(pending_cv_ids, base_dir)

      Logger.info(
        "Download: #{length(to_download)}/#{length(pending_cv_ids)} alt covers to download"
      )

      download_batch(to_download, base_dir, "alt_covers")
    end
  end

  @doc "Download character images that are pending processing."
  def download_characters(base_dir) do
    if skip?() do
      Logger.info("Download: characters skipped (SKIP_IMAGE_DOWNLOAD=true)")
    else
      ch_ids = load_pending_char_image_ids()
      to_download = reject_existing(ch_ids, base_dir)
      Logger.info("Download: #{length(to_download)}/#{length(ch_ids)} characters to download")
      download_batch(to_download, base_dir, "characters")
    end
  end

  @doc "Download screenshot images by their sf_ids."
  def download_screenshots(sf_ids, base_dir) do
    if skip?() do
      Logger.info("Download: screenshots skipped (SKIP_IMAGE_DOWNLOAD=true)")
    else
      to_download = reject_existing(sf_ids, base_dir)
      Logger.info("Download: #{length(to_download)}/#{length(sf_ids)} screenshots to download")
      download_batch(to_download, base_dir, "screenshots")
    end
  end

  defp skip?, do: System.get_env("SKIP_IMAGE_DOWNLOAD") == "true"

  defp load_pending_char_image_ids do
    import Ecto.Query, only: [from: 2]

    from(c in Kaguya.Characters.Character,
      where: not is_nil(c.vndb_image_id) and is_nil(c.primary_image_id),
      select: c.vndb_image_id
    )
    |> Kaguya.Repo.all()
  end

  defp reject_existing(vndb_ids, base_dir) do
    Enum.reject(vndb_ids, fn id ->
      ImagePath.absolute_path(base_dir, id) |> File.exists?()
    end)
  end

  defp download_batch([], _base_dir, category) do
    Logger.info("Download: no #{category} to download")
  end

  defp download_batch(vndb_ids, base_dir, category) do
    Logger.info("Download: downloading #{length(vndb_ids)} #{category}...")

    {success, fail} =
      vndb_ids
      |> Task.async_stream(
        fn id -> download_single(id, base_dir) end,
        max_concurrency: @concurrency,
        timeout: @timeout,
        on_timeout: :kill_task
      )
      |> Enum.reduce({0, 0}, fn
        {:ok, :ok}, {s, f} -> {s + 1, f}
        _, {s, f} -> {s, f + 1}
      end)

    Logger.info("Download: #{category} done (#{success} ok, #{fail} failed)")
  end

  defp download_single(vndb_id, base_dir) do
    rel_path = ImagePath.to_relative_path(vndb_id)
    url = "#{@vndb_image_base}/#{rel_path}"
    dest = ImagePath.absolute_path(base_dir, vndb_id)

    dest |> Path.dirname() |> File.mkdir_p!()

    case Req.get(url, receive_timeout: @timeout) do
      {:ok, %{status: 200, body: body}} ->
        File.write!(dest, body)
        :ok

      {:ok, %{status: status}} ->
        Logger.debug("Download: #{vndb_id} returned HTTP #{status}")
        :error

      {:error, reason} ->
        Logger.debug("Download: #{vndb_id} failed: #{inspect(reason)}")
        :error
    end
  end
end
