defmodule Kaguya.Uploads.VndbImportWorker do
  @moduledoc """
  Oban worker that processes VNDB XML imports in the background.
  """
  use Oban.Worker,
    queue: :import,
    max_attempts: 2,
    unique: [keys: [:upload_id], period: :infinity]

  require Logger

  import Ecto.Query

  alias Kaguya.Repo
  alias Kaguya.Users
  alias Kaguya.Users.VndbImport
  alias Kaguya.VisualNovels.VisualNovel

  @impl true
  def perform(%Oban.Job{args: %{"upload_id" => upload_id, "user_id" => user_id}}) do
    case Repo.get(VndbImport, upload_id) do
      nil ->
        {:cancel, "import record not found"}

      import_record ->
        set_status(import_record, "processing")

        try do
          run_import(import_record, upload_id, user_id)
        rescue
          exception ->
            set_status(import_record, "failed", %{
              error_message: Exception.format(:error, exception, __STACKTRACE__)
            })

            reraise exception, __STACKTRACE__
        end
    end
  end

  defp run_import(import_record, upload_id, user_id) do
    case Kaguya.VndbProcessor.process_vndb_upload(upload_id, user_id) do
      {:ok, result} ->
        set_status(import_record, "completed", %{
          result: serialize_result(result),
          error_message: nil
        })

        auto_enable_category_prefs(user_id)
        enqueue_recs_generation(user_id)
        :ok

      {:error, reason} ->
        message = if is_binary(reason), do: reason, else: inspect(reason)
        set_status(import_record, "failed", %{error_message: message})
        {:error, message}
    end
  end

  # Enqueue a single-user rec generation so the user sees a populated /recs
  # tab shortly after import. Same Oban queue and worker as the weekly cron;
  # concurrency is capped at 1 so these stack instead of fighting over the
  # ~500MB B matrix in RAM. If the user imported but still has <3 rating-like
  # signals, the worker no-ops for them — cheap.
  defp enqueue_recs_generation(user_id) do
    case Kaguya.Recommendations.GenerateWorker.new(%{"user_ids" => [user_id]})
         |> Oban.insert() do
      {:ok, _job} ->
        Logger.info("[VndbImport] Queued rec generation for user #{user_id}")
        :ok

      {:error, changeset} ->
        Logger.warning(
          "[VndbImport] Failed to queue rec generation for user #{user_id}: #{inspect(changeset)}"
        )

        :ok
    end
  end

  defp set_status(import_record, status, extra \\ %{}) do
    attrs = Map.merge(%{status: status}, extra)

    import_record
    |> VndbImport.changeset(attrs)
    |> Repo.update!()
    |> tap(&broadcast_status/1)
  end

  defp broadcast_status(%VndbImport{} = import_record) do
    Phoenix.PubSub.broadcast(
      Kaguya.PubSub,
      "vndb_import:#{import_record.id}",
      {:vndb_import_updated, import_record}
    )
  end

  # After import, check if user's library contains nukige/adjacent VNs.
  # If so, auto-enable the corresponding preferences so they can see their own VNs.
  defp auto_enable_category_prefs(user_id) do
    categories =
      from(rs in Kaguya.Shelves.ReadingStatus,
        join: vn in VisualNovel,
        on: vn.id == rs.visual_novel_id,
        where: rs.user_id == ^user_id and vn.title_category != :vn,
        select: vn.title_category,
        distinct: true
      )
      |> Repo.all()

    updates =
      %{}
      |> then(fn u -> if :nukige in categories, do: Map.put(u, :show_nukige, true), else: u end)
      |> then(fn u ->
        if :adjacent in categories, do: Map.put(u, :show_adjacent, true), else: u
      end)

    if map_size(updates) > 0 do
      Users.update_user(user_id, updates)

      Logger.info(
        "[VndbImport] Auto-enabled category prefs for user #{user_id}: #{inspect(Map.keys(updates))}"
      )
    end
  end

  defp serialize_result(result) do
    %{
      vns_imported: result.vns_imported,
      ratings: result.ratings,
      reviews: result.reviews,
      shelves: result.shelves,
      imported_items: Enum.map(result.imported_items, &serialize_imported_item/1),
      missing_vns: Enum.sort_by(result.missing_vns, & &1.title),
      banned_vns: Enum.sort_by(result.banned_vns, & &1.title)
    }
  end

  defp serialize_imported_item(item) do
    %{
      id: item.id,
      title: item.title,
      slug: item.slug,
      images: serialize_images(item.images),
      has_ero: item.has_ero,
      rating: item.rating,
      status: item.status && Atom.to_string(item.status),
      release_date: item.release_date && Date.to_iso8601(item.release_date),
      date_added: item.date_added && DateTime.to_iso8601(item.date_added),
      date_started: item.date_started && Date.to_iso8601(item.date_started),
      date_finished: item.date_finished && Date.to_iso8601(item.date_finished),
      vote_date: item.vote_date && Date.to_iso8601(item.vote_date)
    }
  end

  defp serialize_images(nil), do: nil
  defp serialize_images(%{} = images), do: Map.new(images, fn {k, v} -> {to_string(k), v} end)
end
