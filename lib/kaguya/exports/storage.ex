defmodule Kaguya.Exports.Storage do
  @moduledoc "Thin S3/R2 wrapper for user export files."

  alias ExAws.S3
  require Logger

  @content_type "application/zip"

  def bucket, do: Application.fetch_env!(:kaguya, :uploads_bucket)

  def export_key(user_id, export_id), do: "users/exports/kaguya/#{user_id}/#{export_id}.zip"

  def upload_export(file_path, user_id, export_id) do
    key = export_key(user_id, export_id)

    file_path
    |> S3.Upload.stream_file()
    |> S3.upload(bucket(), key, content_type: @content_type)
    |> ExAws.request()
    |> case do
      {:ok, _} = ok ->
        Logger.info("Library export uploaded: #{key}")
        ok

      {:error, reason} ->
        Logger.error("Library export upload failed for #{key}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def delete_object(key) when is_binary(key) do
    S3.delete_object(bucket(), key) |> ExAws.request()
  end

  def presign_get(key, expires_in_seconds, filename \\ nil) do
    query_params =
      if filename do
        [{"response-content-disposition", "attachment; filename=\"#{filename}\""}]
      else
        []
      end

    S3.presigned_url(ExAws.Config.new(:s3), :get, bucket(), key,
      expires_in: expires_in_seconds,
      query_params: query_params
    )
  end
end
