defmodule Kaguya.Sync.VndbSyncWorker do
  @moduledoc """
  Oban worker for weekly VNDB sync.

  Scheduled via cron (Sunday 04:00 UTC). Can also be triggered manually:

      Kaguya.Sync.VndbSyncWorker.new(%{}) |> Oban.insert()
  """

  use Oban.Worker, queue: :sync, max_attempts: 2, unique: [period: 21_600]

  @impl Oban.Worker
  def perform(_job) do
    with :ok <- Kaguya.Sync.VndbSync.run() do
      _ = Kaguya.Sitemaps.PublisherWorker.enqueue_full()
      :ok
    end
  end
end
