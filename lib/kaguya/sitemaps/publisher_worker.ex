defmodule Kaguya.Sitemaps.PublisherWorker do
  @moduledoc """
  Oban worker that publishes pre-generated sitemap XML to R2.
  """

  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 3,
    unique: [
      period: 3600,
      states: [:available, :scheduled, :executing, :retryable],
      keys: [:mode]
    ]

  require Logger

  alias Kaguya.Sitemaps.Publisher

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(20)

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    mode = Map.get(args, "mode", "full")
    Publisher.run(mode: mode)
  end

  def enqueue_full do
    enqueue("full")
  end

  def enqueue_user_content do
    enqueue("user_content")
  end

  defp enqueue(mode) do
    %{mode: mode}
    |> new()
    |> Oban.insert()
    |> case do
      {:ok, job} ->
        {:ok, job}

      {:error, reason} = error ->
        Logger.warning("Sitemaps.PublisherWorker enqueue failed",
          mode: mode,
          reason: inspect(reason)
        )

        error
    end
  end
end
