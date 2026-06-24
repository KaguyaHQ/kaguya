defmodule Kaguya.SavedBrowseFilters do
  @moduledoc """
  Context for managing saved VN browse filters.
  """

  import Ecto.Query
  alias Kaguya.Repo
  alias Kaguya.VisualNovels.SavedBrowseFilter

  @doc """
  Lists all saved browse filters for a user.
  """
  def list_for_user(user_id) do
    SavedBrowseFilter
    |> where([f], f.user_id == ^user_id)
    |> order_by([f], desc: f.updated_at)
    |> Repo.all()
  end

  @doc """
  Gets a saved browse filter by ID for a specific user.
  Returns {:ok, filter} or {:error, :not_found}.
  """
  def get_for_user(id, user_id) do
    case Repo.get_by(SavedBrowseFilter, id: id, user_id: user_id) do
      nil -> {:error, :not_found}
      filter -> {:ok, filter}
    end
  end

  @doc """
  Creates a new saved browse filter.
  If is_default is true, clears any existing default for the user.
  """
  def create(user_id, attrs) do
    Repo.transact(fn ->
      if Map.get(attrs, :is_default, false) do
        clear_default(user_id)
      end

      %SavedBrowseFilter{}
      |> SavedBrowseFilter.changeset(Map.put(attrs, :user_id, user_id))
      |> Repo.insert()
    end)
  end

  @doc """
  Updates an existing saved browse filter.
  If is_default is set to true, clears any existing default for the user.
  """
  def update(id, user_id, attrs) do
    Repo.transact(fn ->
      with {:ok, filter} <- get_for_user(id, user_id) do
        if Map.get(attrs, :is_default, false) && !filter.is_default do
          clear_default(user_id)
        end

        filter
        |> SavedBrowseFilter.changeset(attrs)
        |> Repo.update()
      end
    end)
  end

  @doc """
  Deletes a saved browse filter.
  """
  def delete(id, user_id) do
    with {:ok, filter} <- get_for_user(id, user_id),
         {:ok, _} <- Repo.delete(filter) do
      {:ok, true}
    end
  end

  # Clears the is_default flag for all filters belonging to the user
  defp clear_default(user_id) do
    SavedBrowseFilter
    |> where([f], f.user_id == ^user_id and f.is_default == true)
    |> Repo.update_all(set: [is_default: false])
  end
end
