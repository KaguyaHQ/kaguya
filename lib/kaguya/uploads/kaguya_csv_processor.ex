defmodule Kaguya.Uploads.KaguyaCsvProcessor do
  @moduledoc "Processes uploaded Kaguya-native CSV library imports."

  require Logger

  alias ExAws.S3
  alias Kaguya.Exports.KaguyaCsv
  alias Kaguya.Stats.Worker, as: StatsWorker

  def process_upload(upload_id, user_id) do
    temp_key = "users/temp/#{upload_id}"

    with {:ok, csv_data} <- fetch_temp_file(temp_key),
         :ok <- archive_csv(upload_id),
         {:ok, result} <- KaguyaCsv.import_csv(csv_data, user_id) do
      enqueue_post_import_stats_refresh(user_id)
      {:ok, result}
    end
  end

  defp fetch_temp_file(key) do
    case S3.get_object(bucket(), key) |> ExAws.request() do
      {:ok, %{body: body}} ->
        {:ok, body}

      {:error, reason} ->
        Logger.error("Failed to fetch temporary Kaguya CSV #{key}: #{inspect(reason)}")
        {:error, "Failed to fetch uploaded CSV"}
    end
  end

  defp archive_csv(upload_id) do
    temp_key = "users/temp/#{upload_id}"
    permanent_key = "users/kaguya_csv_imports/#{upload_id}.csv"

    case S3.put_object_copy(bucket(), permanent_key, bucket(), temp_key) |> ExAws.request() do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to archive Kaguya CSV import #{upload_id}: #{inspect(reason)}")
        {:error, "Failed to archive uploaded CSV"}
    end
  end

  defp enqueue_post_import_stats_refresh(user_id) do
    StatsWorker.new(%{"type" => "vn_full_snapshot", "user_id" => user_id, "period" => nil})
    |> Oban.insert()
  end

  defp bucket, do: Application.fetch_env!(:kaguya, :uploads_bucket)
end
