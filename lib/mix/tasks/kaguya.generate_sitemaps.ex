defmodule Mix.Tasks.Kaguya.GenerateSitemaps do
  @moduledoc """
  Generate and publish sitemap XML files to R2.

  ## Usage

      mix kaguya.generate_sitemaps
      mix kaguya.generate_sitemaps --mode user_content
      mix kaguya.generate_sitemaps --dry-run

  ## Options

    * `--mode full|user_content` - defaults to `full`
    * `--dry-run` - generate but do not upload
  """

  use Mix.Task

  @shortdoc "Generate and publish sitemap XML files"

  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        strict: [mode: :string, dry_run: :boolean],
        aliases: [m: :mode, n: :dry_run]
      )

    mode = Keyword.get(opts, :mode, "full")
    dry_run? = Keyword.get(opts, :dry_run, false)

    case Kaguya.Sitemaps.Publisher.run(mode: mode, dry_run: dry_run?) do
      :ok -> :ok
      {:error, reason} -> Mix.raise("sitemap publish failed: #{inspect(reason)}")
    end
  end
end
