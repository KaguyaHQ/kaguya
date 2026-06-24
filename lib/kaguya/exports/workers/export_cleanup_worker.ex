defmodule Kaguya.Exports.Workers.ExportCleanupWorker do
  @moduledoc "Deletes expired user library export rows and files."

  use Oban.Worker, queue: :exports, max_attempts: 1

  import Ecto.Query

  alias Kaguya.Exports.Storage
  alias Kaguya.Repo
  alias Kaguya.Users.UserLibraryExport

  @expires_in_days 3
  @terminal_statuses [:completed, :failed]

  @impl true
  def perform(%Oban.Job{}) do
    cutoff = DateTime.add(DateTime.utc_now(), -@expires_in_days * 24 * 3600, :second)

    expired =
      Repo.all(
        from e in UserLibraryExport,
          where: e.inserted_at < ^cutoff and e.status in ^@terminal_statuses,
          select: %{object_key: e.object_key}
      )

    Enum.each(expired, fn %{object_key: key} ->
      if key, do: Storage.delete_object(key)
    end)

    {deleted, _} =
      Repo.delete_all(
        from e in UserLibraryExport,
          where: e.inserted_at < ^cutoff and e.status in ^@terminal_statuses
      )

    {:ok, %{deleted: deleted}}
  end
end
