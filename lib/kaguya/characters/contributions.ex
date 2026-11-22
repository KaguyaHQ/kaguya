defmodule Kaguya.Characters.Contributions do
  @moduledoc "Character contributions with server-staged images and revision history."

  alias Kaguya.{Repo, Revisions}
  alias Kaguya.Users.User

  def create(attrs, summary, user, image \\ nil) do
    with {:ok, user} <- editable_user(user) do
      Revisions.create_entity(:character, with_image(attrs, image, user), summary, user)
    end
  end

  def update(id, attrs, summary, user, base_revision, image \\ nil) do
    with {:ok, user} <- editable_user(user) do
      Repo.transact(fn ->
        Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", ["character:#{id}"])

        Revisions.submit_edit(:character, id, with_image(attrs, image, user), summary, user,
          base_revision: base_revision
        )
      end)
    end
  end

  defp with_image(attrs, nil, _user), do: Map.delete(attrs, :staged_image)

  defp with_image(attrs, %{id: id, flags: flags}, user) do
    attrs
    |> Map.merge(flags)
    |> Map.put(:primary_image_id, id)
    |> Map.put(:staged_image, %{id: id, uploaded_by: user.id, flags: flags})
  end

  defp editable_user(%{id: id}) do
    case Repo.get(User, id) do
      %{can_edit: true} = user -> {:ok, user}
      _ -> {:error, "Editing is disabled for this account."}
    end
  end

  defp editable_user(_user), do: {:error, "Sign in to contribute."}
end
