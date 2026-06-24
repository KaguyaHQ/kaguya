defmodule Kaguya.Uploads.Helpers.VnImportInserter do
  @moduledoc """
  Inserts VN shelves and shelf items into the database during VNDB imports.
  """

  import Ecto.Query
  alias Kaguya.Repo
  alias Kaguya.Shelves.Shelf

  @doc """
  Creates any missing VN shelves and returns the number actually inserted.
  Generates slugs entirely in memory.
  """
  def insert_vn_shelves(user_id, shelf_names, now) do
    # 1) Get the slugs the user already has
    existing_slugs =
      Repo.all(
        from s in Shelf,
          where: s.user_id == ^user_id,
          select: s.slug
      )
      |> MapSet.new()

    # 2) Build the rows, keeping a running MapSet of "seen" slugs
    {rows, _seen} =
      Enum.reduce(shelf_names, {[], existing_slugs}, fn name, {acc_rows, seen} ->
        base = Slug.slugify(name, truncate: 45) || "custom"
        slug = next_unique_slug(base, seen)

        row = %{
          id: UUIDv7.generate(),
          user_id: user_id,
          name: name,
          slug: slug,
          vns_count: 0,
          inserted_at: now,
          updated_at: now
        }

        {[row | acc_rows], MapSet.put(seen, slug)}
      end)

    # 3) Bulk INSERT (still safe thanks to the unique index)
    {count, _} =
      Repo.insert_all(
        Shelf,
        rows,
        on_conflict: :nothing,
        conflict_target: [:user_id, :name]
      )

    count
  end

  # Appends "-1", "-2", … until it is not in MapSet
  defp next_unique_slug(base, seen, n \\ 0) do
    slug = if n == 0, do: base, else: "#{base}-#{n}"

    if MapSet.member?(seen, slug),
      do: next_unique_slug(base, seen, n + 1),
      else: slug
  end

  @doc """
  Retrieves a map of shelf names to their IDs for a user.
  """
  def get_vn_shelves_map(user_id) do
    Shelf
    |> where([s], s.user_id == ^user_id)
    |> Repo.all()
    |> Map.new(fn s -> {s.name, s.id} end)
  end

  @doc """
  Converts shelf_items with shelf_name to use shelf_id.
  """
  def update_vn_shelf_items(shelf_items, shelves_map, now) do
    Enum.map(shelf_items, fn %{shelf_name: shelf_name, visual_novel_id: visual_novel_id} ->
      shelf_id = Map.fetch!(shelves_map, shelf_name)

      %{
        shelf_id: shelf_id,
        visual_novel_id: visual_novel_id,
        inserted_at: now,
        updated_at: now
      }
    end)
  end

  @doc """
  Updates the vns_count for all shelves belonging to a user.
  """
  def update_vn_shelf_counts(user_id) do
    from(s in Shelf,
      where: s.user_id == ^user_id,
      update: [
        set: [
          vns_count:
            fragment(
              "COALESCE((SELECT COUNT(*) FROM shelf_items WHERE shelf_id = ?), 0)",
              s.id
            )
        ]
      ]
    )
    |> Repo.update_all([])
  end
end
