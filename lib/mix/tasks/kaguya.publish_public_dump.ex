defmodule Mix.Tasks.Kaguya.PublishPublicDump do
  @moduledoc """
  Upload a dump archive to Cloudflare R2.

  Typically used after `mix kaguya.export_public_dump` for ad-hoc publishes.
  Routine weekly publishes are handled automatically by
  `Kaguya.PublicDump.PublisherWorker` (Oban cron).

  ## Usage

      mix kaguya.publish_public_dump --archive /tmp/kaguya-dump.tar.zst
      mix kaguya.publish_public_dump --archive ... --dry-run
      mix kaguya.publish_public_dump --archive ... --date 2026-04-30

  ## Options

    * `--archive PATH` (required) — path to a `.tar.zst` produced by
      `mix kaguya.export_public_dump`.
    * `--date YYYY-MM-DD` — override the date used in the dated filename.
      Defaults to today (UTC).
    * `--dry-run` — log what would happen, don't upload anything.
  """

  use Mix.Task

  @shortdoc "Upload a public DB dump archive to R2"

  def run(args) do
    Mix.Task.run("loadpaths")
    Mix.Task.run("app.config")
    {:ok, _} = Application.ensure_all_started(:ex_aws)
    {:ok, _} = Application.ensure_all_started(:req)

    {opts, _, _} =
      OptionParser.parse(args,
        strict: [archive: :string, date: :string, dry_run: :boolean],
        aliases: [a: :archive, d: :date, n: :dry_run]
      )

    archive = Keyword.fetch!(opts, :archive)

    publisher_opts = [
      date: parse_date(Keyword.get(opts, :date)),
      dry_run: Keyword.get(opts, :dry_run, false)
    ]

    case Kaguya.PublicDump.Publisher.run(archive, publisher_opts) do
      :ok -> :ok
      {:error, reason} -> Mix.raise("publish failed: #{inspect(reason)}")
    end
  end

  defp parse_date(nil), do: nil
  defp parse_date(iso), do: Date.from_iso8601!(iso)
end
