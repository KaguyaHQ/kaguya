defmodule Kaguya.Exports.Workers.KaguyaCsvExportWorker do
  @moduledoc "Oban worker that generates Kaguya-native CSV account export ZIPs."

  use Oban.Worker, queue: :exports, max_attempts: 3

  alias Kaguya.Exports.KaguyaCsv
  alias Kaguya.Users

  @impl true
  def perform(%Oban.Job{args: %{"export_id" => export_id}} = job) do
    export = Users.get_user_library_export!(export_id)

    {:ok, export} = Users.update_user_library_export(export, %{status: :processing, error: nil})

    try do
      case KaguyaCsv.perform!(export) do
        {:ok, _updated} ->
          :ok

        {:error, reason} ->
          mark_failed_on_final_attempt(job, export, inspect(reason))
          {:error, reason}
      end
    rescue
      exception ->
        mark_failed_on_final_attempt(
          job,
          export,
          Exception.format(:error, exception, __STACKTRACE__)
        )

        reraise exception, __STACKTRACE__
    end
  end

  defp mark_failed_on_final_attempt(
         %Oban.Job{attempt: attempt, max_attempts: max_attempts},
         export,
         error
       )
       when attempt >= max_attempts do
    Users.update_user_library_export(export, %{status: :failed, error: error})
  end

  defp mark_failed_on_final_attempt(_job, _export, _error), do: :ok
end
