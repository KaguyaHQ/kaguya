defmodule Kaguya.Exports.Workers.ExportCleanupWorkerTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Kaguya.Exports.Workers.ExportCleanupWorker
  alias Kaguya.Repo
  alias Kaguya.Users.{User, UserLibraryExport}

  setup do
    :ok = Sandbox.checkout(Repo)
    :ok
  end

  test "deletes only expired terminal export rows" do
    user = insert_user!()

    old =
      DateTime.utc_now() |> DateTime.add(-4 * 24 * 3600, :second) |> DateTime.truncate(:second)

    completed = insert_export!(user, :completed, old)
    queued = insert_export!(user, :queued, old)

    assert {:ok, %{deleted: 1}} = ExportCleanupWorker.perform(%Oban.Job{args: %{}})

    refute Repo.get(UserLibraryExport, completed.id)
    assert Repo.get(UserLibraryExport, queued.id)
  end

  defp insert_user! do
    id = UUIDv7.generate()
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert!(%User{
      id: id,
      email: "#{id}@example.com",
      username: "u#{String.slice(id, 0, 8)}",
      display_name: "User #{String.slice(id, 0, 4)}",
      inserted_at: now,
      updated_at: now
    })
  end

  defp insert_export!(user, status, inserted_at) do
    Repo.insert!(%UserLibraryExport{
      user_id: user.id,
      status: status,
      inserted_at: inserted_at,
      updated_at: inserted_at
    })
  end
end
