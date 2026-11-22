defmodule Kaguya.Lists.Query do
  @moduledoc false

  import Ecto.Query

  alias Kaguya.Lists.{List, ListItem}

  def visible(query \\ List) do
    from(l in query, where: l.is_public == true and is_nil(l.hidden_at))
  end

  def visible_to(query, nil), do: where(query, [l], is_nil(l.hidden_at))

  def visible_to(query, viewer_id) do
    where(query, [l], is_nil(l.hidden_at) or l.user_id == ^viewer_id)
  end

  def filter_by_allowed_categories(query, nil), do: query

  # Safe-mode scoping: a list is shown when it holds at least one allowed VN.
  # Character lists qualify through the VNs their characters appear in.
  def filter_by_allowed_categories(query, allowed) do
    allowed_strings = Enum.map(allowed, &to_string/1)

    where(
      query,
      [l],
      fragment(
        """
        CASE ?
          WHEN 'character' THEN EXISTS (
            SELECT 1 FROM list_character_items lci
            JOIN vn_characters vc ON vc.character_id = lci.character_id
            JOIN visual_novels vn ON vn.id = vc.visual_novel_id
            WHERE lci.list_id = ? AND vn.title_category = ANY(?)
          )
          ELSE EXISTS (
            SELECT 1 FROM list_items li
            JOIN visual_novels vn ON vn.id = li.visual_novel_id
            WHERE li.list_id = ? AND vn.title_category = ANY(?)
          )
        END
        """,
        l.item_type,
        l.id,
        ^allowed_strings,
        l.id,
        ^allowed_strings
      )
    )
  end

  def for_user(query, user_id) do
    where(query, [l], l.user_id == ^user_id)
  end

  def for_vn(query, vn_id) do
    from([l] in query,
      join: vl in ListItem,
      on: vl.list_id == l.id,
      where: vl.visual_novel_id == ^vn_id
    )
  end
end
