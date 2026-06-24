defmodule Kaguya.Uploads.KaguyaCsvImportWorker do
  @moduledoc "Oban worker that processes Kaguya CSV library imports."

  use Oban.Worker,
    queue: :import,
    max_attempts: 2,
    unique: [keys: [:upload_id], period: :infinity]

  alias Kaguya.Repo
  alias Kaguya.Users.VndbImport

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
    case Kaguya.Uploads.KaguyaCsvProcessor.process_upload(upload_id, user_id) do
      {:ok, result} ->
        set_status(import_record, "completed", %{
          result: serialize_result(result),
          error_message: nil
        })

        enqueue_recs_generation(user_id)
        :ok

      {:error, reason} ->
        message = if is_binary(reason), do: reason, else: inspect(reason)
        set_status(import_record, "failed", %{error_message: message})
        {:error, message}
    end
  end

  defp enqueue_recs_generation(user_id) do
    Kaguya.Recommendations.GenerateWorker.new(%{"user_ids" => [user_id]})
    |> Oban.insert()

    :ok
  end

  defp set_status(import_record, status, extra \\ %{}) do
    attrs = Map.merge(%{status: status}, extra)

    import_record
    |> VndbImport.changeset(attrs)
    |> Repo.update!()
  end

  defp serialize_result(result) do
    %{
      rows: result.rows,
      vns_imported: result.vns_imported,
      ratings: result.ratings,
      reviews: result.reviews,
      shelves: result.shelves,
      shelf_items: result.shelf_items,
      imported_items: Enum.map(result.imported_items, &serialize_imported_item/1),
      missing_vns: Enum.map(result.missing_vns, &serialize_missing_vn/1)
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

  defp serialize_missing_vn(vn) do
    %{
      vn_id: vn.vn_id,
      title: vn.title,
      slug: vn.slug
    }
  end
end
