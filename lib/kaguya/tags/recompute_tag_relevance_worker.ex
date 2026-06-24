defmodule Kaguya.Tags.RecomputeTagRelevanceWorker do
  @moduledoc """
  Oban worker for weekly recomputation of tag relevance scores.

  Scheduled via cron in config/config.exs:

      {"10 3 * * 0", Kaguya.Tags.RecomputeTagRelevanceWorker}  # Sunday 03:10
  """

  use Oban.Worker, queue: :maintenance, max_attempts: 1

  alias Kaguya.Tags.TagRelevance

  @impl Oban.Worker
  def perform(_job) do
    TagRelevance.recompute_all_vn_tags()
  end
end
