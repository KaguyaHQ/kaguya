defmodule Kaguya.VisualNovels.TitleCategory do
  @moduledoc """
  Defines VN content categories and maps ban reasons to categories.

  Two things to adjust here:
    1. `@permanently_banned_reasons` — these stay deleted, never re-imported
    2. Everything else in `banned_vndb_ids` that ISN'T in that list gets
       categorized as nukige or adjacent based on `@nukige_reasons`

  If a new ban reason appears (e.g. "necrophilia"), it automatically becomes
  adjacent unless you add it to `@permanently_banned_reasons` or `@nukige_reasons`.
  """

  @categories [:vn, :nukige, :adjacent]

  # These stay permanently banned — never unban, never import
  @permanently_banned_reasons ["csam policy", "Gacha"]

  # Ban reasons that map to the nukige category
  @nukige_reasons ["nukige"]

  # Everything else that's banned but NOT in @permanently_banned_reasons
  # and NOT in @nukige_reasons automatically becomes adjacent.
  # No need to enumerate adjacent reasons — it's the fallback.

  def categories, do: @categories
  def default, do: :vn

  def permanently_banned_reasons, do: @permanently_banned_reasons
  def nukige_reasons, do: @nukige_reasons

  @doc "Returns the category for a ban reason, or nil if permanently banned."
  def category_for_ban_reason(reason) do
    cond do
      reason in @permanently_banned_reasons -> nil
      reason in @nukige_reasons -> :nukige
      true -> :adjacent
    end
  end

  @doc "Returns the list of allowed categories for a user's preferences."
  def allowed_categories(user) do
    cats = [:vn]
    cats = if Map.get(user, :show_nukige, false), do: cats ++ [:nukige], else: cats
    cats = if Map.get(user, :show_adjacent, true), do: cats ++ [:adjacent], else: cats
    cats
  end
end
