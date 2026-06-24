defmodule Kaguya.PublicDump.Publisher do
  @moduledoc """
  Upload a dump archive to Cloudflare R2.

  Pipeline:

    1. Verify archive exists + is `.tar.zst`
    2. Stream-upload dated archive `kaguya-db-YYYY-MM-DD.tar.zst` (immutable)
    3. Server-side copy to `kaguya-db-latest.tar.zst` (1-hour cache)
    4. Best-effort prune of dated archives older than `@retention` most
       recent — failures here log a warning but don't unwind the publish

  Re-running on the same archive (same date) overwrites with identical
  bytes. Idempotent.

  Modeled on VNDB's `dl.vndb.org/dump/` — a stable "latest" URL plus a
  small history of dated archives. No manifest, no SHA-256 sidecar, no
  per-file metadata file. Consumers download the file; that's it.

  Re-uses the existing R2 setup (`:ex_aws` credentials + `:uploads_bucket`
  config). All dump objects sit under the `dumps/` key prefix; consumers
  fetch them at `https://images.kaguya.io/dumps/...`.
  """

  require Logger

  alias ExAws.S3

  @retention 3
  @key_prefix "dumps/"
  @public_url_base "https://images.kaguya.io"
  @dated_cache "public, max-age=31536000, immutable"
  @latest_cache "public, max-age=3600, must-revalidate"
  @latest_archive_basename "kaguya-db-latest.tar.zst"
  @dated_archive_regex ~r/^kaguya-db-\d{4}-\d{2}-\d{2}\.tar\.zst$/

  @type archive :: %{
          filename: String.t(),
          size: non_neg_integer(),
          last_modified: String.t(),
          url: String.t()
        }

  @doc """
  List published archives in R2.

  Returns the `latest` pointer (or `nil` if no publish has happened yet)
  and a list of dated archives sorted newest-first. The dated archive
  matching `latest` (same `last_modified`) is excluded from `past` so
  the same content isn't surfaced twice in the UI.

  Used by `KaguyaWeb.DumpsController` so the public `/dumps` page can
  render without doing N HEAD requests against R2 — that path is rate-
  limited by Cloudflare WAF for some egress IPs.
  """
  @spec list_published() ::
          {:ok, %{latest: archive | nil, past: [archive]}} | {:error, term()}
  def list_published do
    bucket = Application.fetch_env!(:kaguya, :uploads_bucket)

    case bucket
         |> S3.list_objects_v2(prefix: @key_prefix)
         |> ExAws.request() do
      {:ok, %{body: %{contents: contents}}} ->
        archives = Enum.map(contents, &to_archive/1)
        latest = Enum.find(archives, &(&1.filename == @latest_archive_basename))

        past =
          archives
          |> Enum.filter(&Regex.match?(@dated_archive_regex, &1.filename))
          |> reject_duplicate_of(latest)
          |> Enum.sort_by(& &1.filename, :desc)

        {:ok, %{latest: latest, past: past}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp to_archive(obj) do
    basename = Path.basename(obj.key)

    %{
      filename: basename,
      size: parse_size(obj.size),
      last_modified: obj.last_modified,
      url: public_url(basename)
    }
  end

  defp parse_size(v) when is_integer(v), do: v
  defp parse_size(v) when is_binary(v), do: String.to_integer(v)

  defp reject_duplicate_of(archives, nil), do: archives

  # `latest` is a server-side copy of the most recent dated archive, so the
  # two have nearly-identical (but not equal) last_modified timestamps.
  # Compare on the date in the filename matching latest's modification day.
  defp reject_duplicate_of(archives, %{last_modified: lm}) do
    case last_modified_date(lm) do
      nil -> archives
      date -> Enum.reject(archives, &(&1.filename == dated_filename(date)))
    end
  end

  defp last_modified_date(iso) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt, _} -> DateTime.to_date(dt)
      _ -> nil
    end
  end

  defp last_modified_date(_), do: nil

  @doc """
  Publish an archive to R2.

  Options:
    * `:date` — `Date.t()` for the dated filename. Defaults to today (UTC).
    * `:dry_run` — log all actions, perform no uploads.
  """
  def run(archive_path, opts \\ []) do
    date = Keyword.get(opts, :date) || Date.utc_today()
    dry_run? = Keyword.get(opts, :dry_run, false)
    bucket = Application.fetch_env!(:kaguya, :uploads_bucket)

    with :ok <- check_archive(archive_path) do
      filename = dated_filename(date)

      Logger.info("PublicDump.Publisher: starting",
        date: Date.to_iso8601(date),
        size_bytes: File.stat!(archive_path).size
      )

      if dry_run? do
        Logger.info("PublicDump.Publisher: DRY RUN — no uploads")
        :ok
      else
        do_publish(archive_path, filename, bucket)
      end
    end
  end

  defp do_publish(archive_path, dated_basename, bucket) do
    with {:ok, _} <- upload_dated_archive(archive_path, dated_basename, bucket),
         {:ok, _} <- copy_to_latest(dated_basename, bucket) do
      # Best-effort: cleanup failures shouldn't unwind a successful publish.
      _ = prune_old_archives(bucket)

      Logger.info("PublicDump.Publisher: done",
        latest_url: public_url(@latest_archive_basename),
        dated_url: public_url(dated_basename)
      )

      :ok
    end
  end

  # ── pipeline steps ─────────────────────────────────────────────────────────

  defp check_archive(path) do
    cond do
      not File.exists?(path) -> {:error, {:archive_not_found, path}}
      not String.ends_with?(path, ".tar.zst") -> {:error, {:not_tar_zst, path}}
      true -> :ok
    end
  end

  # Streamed multipart upload — peak memory ~5 MB regardless of archive size.
  defp upload_dated_archive(local_path, basename, bucket) do
    key = key_for(basename)
    Logger.info("PublicDump.Publisher: uploading #{key}")

    local_path
    |> S3.Upload.stream_file()
    |> S3.upload(bucket, key,
      content_type: "application/zstd",
      cache_control: @dated_cache,
      content_disposition: ~s|attachment; filename="#{basename}"|
    )
    |> ExAws.request()
  end

  defp copy_to_latest(dated_basename, bucket) do
    dated_key = key_for(dated_basename)
    latest_key = key_for(@latest_archive_basename)

    Logger.info("PublicDump.Publisher: copying to #{latest_key}")

    bucket
    |> S3.put_object_copy(latest_key, bucket, dated_key,
      cache_control: @latest_cache,
      content_disposition: ~s|attachment; filename="#{dated_basename}"|,
      metadata_directive: "REPLACE"
    )
    |> ExAws.request()
  end

  # Best-effort: any failure is logged but doesn't fail the run. The next
  # successful publish will catch up on any orphaned archives. Listing is
  # not paginated — at retention=3 + weekly cadence, the matching key set
  # stays well under the 1000-key default page size.
  defp prune_old_archives(bucket) do
    case bucket
         |> S3.list_objects_v2(prefix: key_for("kaguya-db-"))
         |> ExAws.request() do
      {:ok, %{body: %{contents: contents}}} ->
        contents
        |> Enum.map(& &1.key)
        |> Enum.filter(&Regex.match?(@dated_archive_regex, Path.basename(&1)))
        |> Enum.sort(:desc)
        |> Enum.drop(@retention)
        |> Enum.each(&delete_quietly(&1, bucket))

        :ok

      {:error, reason} ->
        Logger.warning("PublicDump.Publisher: prune list failed; skipping",
          reason: inspect(reason)
        )

        :ok
    end
  end

  defp delete_quietly(key, bucket) do
    Logger.info("PublicDump.Publisher: pruning #{key}")

    try do
      case bucket |> S3.delete_object(key) |> ExAws.request() do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          Logger.warning("PublicDump.Publisher: delete failed",
            key: key,
            reason: inspect(reason)
          )
      end
    rescue
      e ->
        Logger.warning("PublicDump.Publisher: delete raised",
          key: key,
          error: inspect(e)
        )
    end
  end

  # ── helpers ────────────────────────────────────────────────────────────────

  defp dated_filename(date), do: "kaguya-db-#{Date.to_iso8601(date)}.tar.zst"

  defp key_for(basename), do: @key_prefix <> basename

  defp public_url(basename), do: @public_url_base <> "/" <> key_for(basename)
end
