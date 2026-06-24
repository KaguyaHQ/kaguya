defmodule Kaguya.VndbProcessor do
  @moduledoc """
  Handles VNDB XML processing tasks such as parsing uploaded XML files and importing data.
  """

  require Logger
  # import Ecto.Query  # YEAR-STATS DISABLED — only needed by commented year queries below

  alias ExAws.S3
  alias Kaguya.Activities
  # alias Kaguya.Repo  # YEAR-STATS DISABLED
  # alias Kaguya.Shelves.ReadingStatus  # YEAR-STATS DISABLED
  # alias Kaguya.Stats.UserPeriodStat  # YEAR-STATS DISABLED
  alias Kaguya.Stats.Worker, as: StatsWorker
  alias Kaguya.Uploads.VndbImporter

  @doc """
  Processes the uploaded VNDB XML file.

  ## Parameters
    - `upload_id`: The UUID of the uploaded XML.
    - `user_id`: The ID of the user who uploaded the file.
  """
  def process_vndb_upload(upload_id, user_id) do
    temp_key = build_temp_key(upload_id)

    with {:ok, xml_data} <- fetch_temp_xml(temp_key),
         :ok <- check_size(xml_data),
         {:ok, result} <- VndbImporter.parse_and_insert_vns(xml_data, user_id),
         :ok <- move_xml_to_permanent_location(upload_id) do
      enqueue_post_import_stats_refresh(user_id)
      record_import_activity(user_id, upload_id, result)
      {:ok, result}
    end
  end

  # Authoritative server-side enforcement of the 1.5 MB cap. The dropzone has
  # a matching client-side check for fast feedback, but that's UX — anyone can
  # bypass it (devtools, curl, anything that hits the presigned URL directly),
  # so this guard is the actual security boundary. Lives in one place
  # (Kaguya.Uploads.max_vndb_xml_bytes/0) so the limit is auditable.
  defp check_size(xml_data) do
    if byte_size(xml_data) > Kaguya.Uploads.max_vndb_xml_bytes() do
      {:error, "XML file exceeds the 1.5 MB limit"}
    else
      :ok
    end
  end

  # Imports can add hundreds of finished VNs at once. Waiting for the daily
  # cron would leave the user staring at empty stats for up to 24h, so kick
  # off an all-time snapshot rebuild asynchronously. The actual computation
  # happens later on the :stats queue.
  #
  # Year-specific stats are currently disabled, so only the nil snapshot is
  # enqueued. When year stats come back, restore the commented block below
  # which also enqueues jobs for every year currently in the user's dated
  # reading_statuses AND every year that already has a snapshot row.
  defp enqueue_post_import_stats_refresh(user_id) do
    StatsWorker.new(%{
      "type" => "vn_full_snapshot",
      "user_id" => user_id,
      "period" => nil
    })
    |> Oban.insert()

    # YEAR-STATS DISABLED — revive the full version below when year pages come back.
    #
    # current_years =
    #   from(rs in ReadingStatus,
    #     where: rs.user_id == ^user_id and not is_nil(rs.date_finished),
    #     select: fragment("DISTINCT EXTRACT(year FROM ?)::int", rs.date_finished)
    #   )
    #   |> Repo.all()
    #
    # snapshot_years =
    #   from(s in UserPeriodStat,
    #     where: s.user_id == ^user_id and not is_nil(s.period),
    #     select: s.period
    #   )
    #   |> Repo.all()
    #
    # years = Enum.uniq(current_years ++ snapshot_years)
    # periods = [nil | years]
    #
    # jobs =
    #   Enum.map(periods, fn period ->
    #     StatsWorker.new(%{
    #       "type" => "vn_full_snapshot",
    #       "user_id" => user_id,
    #       "period" => period
    #     })
    #   end)
    #
    # Oban.insert_all(jobs)
  end

  defp record_import_activity(user_id, upload_id, result) do
    Activities.record_activity(%{
      user_id: user_id,
      action: :imported_vndb,
      entity_type: "vndb_import",
      entity_id: upload_id,
      metadata: %{
        vns_imported: result.vns_imported,
        ratings: result.ratings,
        reviews: result.reviews
      }
    })
  end

  # Fetch the temporary XML from S3
  defp fetch_temp_xml(temp_key) do
    bucket = fetch_uploads_bucket()

    case S3.get_object(bucket, temp_key) |> ExAws.request() do
      {:ok, %{body: body}} ->
        {:ok, body}

      {:error, reason} ->
        Logger.error("Failed to fetch temporary XML #{temp_key}: #{inspect(reason)}")
        {:error, "Failed to fetch temporary XML"}
    end
  end

  # Move the XML from temporary to permanent location
  defp move_xml_to_permanent_location(upload_id) do
    temp_key = build_temp_key(upload_id)
    permanent_key = build_permanent_key(upload_id)
    bucket = fetch_uploads_bucket()

    case S3.put_object_copy(bucket, permanent_key, bucket, temp_key)
         |> ExAws.request() do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to move XML to permanent location: #{inspect(reason)}")
        {:error, "Failed to move XML to permanent location"}
    end
  end

  # Helper to build the temporary key
  defp build_temp_key(upload_id), do: "users/temp/#{upload_id}"

  # Helper to build the permanent key for XML
  defp build_permanent_key(upload_id), do: "users/vndb_files/#{upload_id}.xml"

  # Fetch the uploads bucket dynamically
  defp fetch_uploads_bucket do
    Application.fetch_env!(:kaguya, :uploads_bucket)
  end
end
