defmodule Kaguya.Characters.Appearances do
  @moduledoc false

  import Ecto.Query

  alias Kaguya.Characters.VNCharacter
  alias Kaguya.Repo
  alias Kaguya.VisualNovels.{VisualNovel, VNTitle}

  def list_for_edit(character_id, show_hidden?) do
    from(vc in VNCharacter,
      join: vn in assoc(vc, :visual_novel),
      where: vc.character_id == ^character_id,
      order_by: [asc: vn.title, asc: vn.id],
      select: %{
        id: vn.id,
        title: vn.title,
        slug: vn.slug,
        hidden_at: vn.hidden_at,
        role: vc.role,
        spoiler_level: vc.spoiler_level
      }
    )
    |> Repo.all()
    |> Enum.map(fn row ->
      row =
        if row.hidden_at && !show_hidden?,
          do: %{row | title: "Hidden visual novel", slug: nil},
          else: row

      row
      |> Map.drop([:hidden_at])
      |> Map.merge(%{role: to_string(row.role), spoiler_level: to_string(row.spoiler_level)})
    end)
  end

  def search(query, show_hidden?) do
    query = query |> String.trim() |> String.slice(0, 100)

    if String.length(query) < 2 do
      []
    else
      pattern = "%" <> String.replace(query, ["\\", "%", "_"], &("\\" <> &1)) <> "%"

      titles =
        from(t in VNTitle,
          where: ilike(t.title, ^pattern) or ilike(t.latin, ^pattern),
          select: t.visual_novel_id
        )

      from(vn in VisualNovel,
        where: ilike(vn.title, ^pattern) or vn.id in subquery(titles),
        order_by: [asc: vn.title, asc: vn.id],
        limit: 10,
        select: %{id: vn.id, title: vn.title, slug: vn.slug}
      )
      |> visible_query(show_hidden?)
      |> Repo.all()
    end
  end

  defp visible_query(query, true), do: query
  defp visible_query(query, false), do: where(query, [vn], is_nil(vn.hidden_at))

  def validate(character_id, appearances) when is_list(appearances) do
    Enum.reduce_while(appearances, {:ok, []}, fn attrs, {:ok, rows} ->
      case %VNCharacter{character_id: character_id}
           |> VNCharacter.changeset(Map.put(attrs, :character_id, character_id))
           |> Ecto.Changeset.apply_action(:insert) do
        {:ok, row} -> {:cont, {:ok, [row | rows]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
    |> unique_vns()
  end

  def validate(_character_id, _appearances), do: {:error, "Invalid visual novel appearances."}

  defp unique_vns({:ok, rows}) do
    ids = Enum.map(rows, & &1.visual_novel_id)

    if length(ids) == length(Enum.uniq(ids)),
      do: {:ok, Enum.reverse(rows)},
      else: {:error, "A visual novel can only be linked once."}
  end

  defp unique_vns(error), do: error
end
