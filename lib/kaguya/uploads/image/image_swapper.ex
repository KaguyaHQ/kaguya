defmodule Kaguya.ImageSwapper do
  @moduledoc "Swap a record's image pointer and purge its old variants."

  import Ecto.Query
  alias Kaguya.{Repo, Users, Users.User, Images, ImageStorage}
  require Logger

  # ───────────────────────── PUBLIC ──────────────────────────
  def swap_user_image(user_id, :avatar = type, new_id),
    do: do_swap_user_image(user_id, type, :avatar_id, new_id)

  def swap_user_image(user_id, :banner = type, new_id),
    do: do_swap_user_image(user_id, type, :banner_id, new_id)

  # ───────────────────────── PRIVATE ─────────────────────────

  defp do_swap_user_image(user_id, type, field, new_id) do
    Repo.transact(fn ->
      # Lock the row so concurrent swaps serialize
      user =
        User
        |> where(id: ^user_id)
        |> lock("FOR UPDATE")
        |> Repo.one()

      case user do
        nil ->
          {:error, :not_found}

        user ->
          old_id = Map.get(user, field)

          with {:ok, _} <- Users.update_user(user, %{field => new_id}) do
            # Idempotency guard: if old_id == new_id we're being re-run
            # against an already-completed swap (e.g. an Oban worker retry
            # after the previous attempt committed but failed to ack).
            # Deleting old_id's variants in that case would wipe the
            # variants we just generated. Skip the delete; the row is
            # already in the desired state.
            if old_id != new_id, do: delete_variants(type, old_id)
            Logger.warning("ImageSwapper.#{type} user=#{user_id} old=#{old_id} new=#{new_id}")
            {:ok, true}
          end
      end
    end)
  end

  @default_avatar_ids Images.default_avatar_ids()
  @purgeable_types [:avatar, :banner]
  # Purge helper
  defp delete_variants(_type, nil), do: :ok
  defp delete_variants(:avatar, id) when id in @default_avatar_ids, do: :ok

  defp delete_variants(type, id) when type in @purgeable_types do
    for suffix <- Images.suffixes(type) do
      key = Images.key(type, id, suffix)

      case ImageStorage.delete(key) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.warning("Failed to delete #{key}: #{inspect(reason)}")
      end
    end

    :ok
  end

  defp delete_variants(_type, _id), do: :ok
end
