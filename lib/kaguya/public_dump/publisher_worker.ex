defmodule Kaguya.PublicDump.PublisherWorker do
  @moduledoc """
  Weekly Oban worker that generates the public DB dump and uploads it to R2.

  Scheduled in `config/config.exs` Oban crontab at `0 0 * * 0`
  (Sunday 00:00 UTC). Runtime is normally ~2 minutes (10 s export +
  ~60 s upload); the 30-minute timeout is generous-but-bounded.

  Re-uses the same R2 bucket as image uploads (`:uploads_bucket`); dump
  objects sit under the `dumps/` key prefix. To disable temporarily,
  comment out the cron entry in `config/config.exs`.

  Idempotent: if a run is retried, the dated archive is overwritten
  with identical bytes.
  """

  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 3,
    unique: [
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable]
    ]

  require Logger

  alias Kaguya.PublicDump
  alias Kaguya.PublicDump.Publisher

  @timeout :timer.minutes(30)
  # 1 GB free required in /tmp before we even start (export + final tar)
  @min_free_bytes 1_073_741_824

  @impl Oban.Worker
  def timeout(_job), do: @timeout

  @impl Oban.Worker
  def perform(_job) do
    date = Date.utc_today()
    output = Path.join(System.tmp_dir!(), "kaguya-dump-#{Date.to_iso8601(date)}")
    archive = output <> ".tar.zst"
    staging = output <> ".staging"

    Logger.info("PublicDump.PublisherWorker: starting", date: Date.to_iso8601(date))

    try do
      with :ok <- check_disk_space(),
           :ok <- PublicDump.run(output: output),
           :ok <- Publisher.run(archive, date: date) do
        Logger.info("PublicDump.PublisherWorker: done", date: Date.to_iso8601(date))
        :ok
      end
    after
      File.rm_rf(staging)
      File.rm_rf(archive)
    end
  rescue
    e ->
      Kaguya.Observability.ErrorReporter.report(e,
        operation: "public_dump.publish",
        critical: true,
        stacktrace: __STACKTRACE__
      )

      Logger.error("PublicDump.PublisherWorker raised",
        worker: "PublicDump.PublisherWorker",
        error: inspect(e)
      )

      reraise(e, __STACKTRACE__)
  end

  defp check_disk_space do
    case System.cmd("df", ["-k", System.tmp_dir!()], stderr_to_stdout: true) do
      {output, 0} ->
        free_kb =
          output
          |> String.split("\n", trim: true)
          |> Enum.at(1, "")
          |> String.split(~r/\s+/, trim: true)
          |> Enum.at(3, "0")
          |> Integer.parse()

        case free_kb do
          {kb, _} when kb * 1024 >= @min_free_bytes -> :ok
          {kb, _} -> {:error, {:disk_full, kb}}
          # Couldn't parse — proceed and let the export fail later if it
          # really runs out. Don't block on a bad parse.
          :error -> :ok
        end

      _ ->
        # `df` failed for some reason — proceed.
        :ok
    end
  end
end
