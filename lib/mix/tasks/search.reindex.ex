defmodule Mix.Tasks.Search.Reindex do
  @moduledoc """
  Configure and populate Meilisearch from the local database.

      mix search.reindex
      mix search.reindex --only visual_novels

  `--only` accepts visual_novels, characters, or producers. This waits for all
  submitted indexing tasks, and fails if Meilisearch rejects any task.
  `--if-available` is used by setup to skip an unavailable search service.
  """
  use Mix.Task

  alias Kaguya.Search.Client
  alias Kaguya.SearchIndex

  @shortdoc "Populate Meilisearch from the database"
  @indexes ["visual_novels", "characters", "producers"]

  @impl Mix.Task
  def run(args) do
    opts = parse_args(args)

    Mix.Task.run("app.config")

    Application.put_env(
      :kaguya,
      KaguyaWeb.Endpoint,
      Application.fetch_env!(:kaguya, KaguyaWeb.Endpoint)
      |> Keyword.put(:server, false)
    )

    Mix.Task.run("app.start")

    reindex_or_skip(opts)
  end

  defp reindex_or_skip(opts) do
    cond do
      opts[:if_available] == true and not (SearchIndex.writable?() and Client.healthy?()) ->
        Mix.shell().info(
          "Search skipped. Start `mise run search`, then run `mix search.reindex`."
        )

      not SearchIndex.writable?() ->
        Mix.raise(
          "Search indexing needs a configured Meilisearch URL (localhost or 127.0.0.1 in dev)."
        )

      true ->
        indexes = if opts[:only], do: [opts[:only]], else: @indexes
        Enum.each(indexes, &reindex/1)
    end
  end

  defp parse_args(args) do
    {opts, rest, invalid} =
      OptionParser.parse(args, strict: [only: :string, if_available: :boolean])

    if rest != [] or invalid != [] or (opts[:only] && opts[:only] not in @indexes) do
      Mix.raise("Usage: mix search.reindex [--only visual_novels|characters|producers]")
    end

    opts
  end

  defp reindex(index) do
    Mix.shell().info("Reindexing #{index}...")
    {microseconds, count} = :timer.tc(fn -> SearchIndex.reindex(index) end)
    seconds = Float.round(microseconds / 1_000_000, 2)
    Mix.shell().info("#{index}: #{count} documents indexed in #{seconds}s (tasks completed).")
  end
end
