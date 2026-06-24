defmodule Kaguya.Activities.GroupedFeed do
  @moduledoc """
  Pure grouping rules for the home activity feed.

  Walks an ordered list of `%UserActivity{}` (newest first) and merges
  consecutive rows that share `(user_id, action, context_key)` for the
  four actions that summarise visually as a single entry. Mirrors the
  legacy frontend rule from `activityUtils.ts:groupActivityItems`.

  Grouping keys:

    * `:liked_screenshot` / `:liked_cover` — `metadata["vn_slug"]`
    * `:status_changed` — `metadata["status"]`
    * `:followed` — `entity_type` (user-follows and producer-follows stay
      in separate runs so the rendered summary doesn't mix link types).

  All other actions are non-groupable; each becomes a singleton entry.
  """

  # Representative + up to two extras for sentence-style summaries
  # ("X and Y and N more"). Excess rows still bump `:group_size`.
  @members_cap 3

  # Bounds work per entry. Beyond this, the run starts a fresh entry;
  # remaining rows either roll into that entry or get picked up by the
  # next page.
  @group_size_cap 200

  @groupable_actions [:liked_screenshot, :liked_cover, :status_changed, :followed]

  @type entry :: %{
          id: term(),
          representative: map(),
          group_size: pos_integer(),
          members: [map()],
          last_member: map()
        }

  @doc "How many member rows are kept in `:members`."
  def members_cap, do: @members_cap

  @doc "Hard cap on `:group_size` per entry."
  def group_size_cap, do: @group_size_cap

  @doc """
  Groups raw activities (in feed order) into entries.

  Each entry exposes:

    * `:id` — stable id of the representative row
    * `:representative` — head activity (the one rendered)
    * `:group_size` — total rows merged into this entry (capped)
    * `:members` — first `members_cap/0` rows including the representative
    * `:last_member` — deepest (oldest) raw row consumed; used as the
      cursor anchor by callers
  """
  def group_entries(activities) when is_list(activities) do
    {entries, _last_key} = Enum.reduce(activities, {[], nil}, &accumulate/2)
    Enum.reverse(entries)
  end

  defp accumulate(activity, {[head | rest], last_key}) do
    key = grouping_key(activity)

    if key != nil and key == last_key and head.group_size < @group_size_cap do
      {[extend(head, activity) | rest], key}
    else
      {[new_entry(activity), head | rest], key}
    end
  end

  defp accumulate(activity, {[], _}) do
    {[new_entry(activity)], grouping_key(activity)}
  end

  defp new_entry(a) do
    %{
      id: a.id,
      representative: a,
      group_size: 1,
      members: [a],
      last_member: a
    }
  end

  defp extend(%{members: members, group_size: n} = entry, a) do
    members = if length(members) < @members_cap, do: members ++ [a], else: members
    %{entry | members: members, group_size: n + 1, last_member: a}
  end

  defp grouping_key(%{action: action, user_id: uid, entity_type: etype, metadata: meta})
       when action in @groupable_actions do
    case {action, meta} do
      {act, %{"vn_slug" => slug}}
      when act in [:liked_screenshot, :liked_cover] and is_binary(slug) ->
        {uid, act, slug}

      {:status_changed, %{"status" => s}} when is_binary(s) ->
        {uid, :status_changed, s}

      {:followed, _} ->
        {uid, :followed, etype}

      _ ->
        nil
    end
  end

  defp grouping_key(_), do: nil
end
