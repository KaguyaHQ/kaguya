defmodule KaguyaWeb.Comments.Tree do
  @moduledoc """
  Builds a bounded comment tree from a flat, oldest-sorted comment page.
  """

  @max_depth 5

  def max_depth, do: @max_depth

  def build(nil), do: []
  def build([]), do: []

  def build(comments) when is_list(comments) do
    comments = Enum.filter(comments, &valid_comment?/1)

    node_map =
      Map.new(comments, fn comment ->
        {comment.id, %{comment: comment, child_ids: []}}
      end)

    {node_map, roots} =
      Enum.reduce(comments, {node_map, []}, fn comment, {nodes, roots} ->
        parent_id = Map.get(comment, :parent_comment_id)

        if is_binary(parent_id) and Map.has_key?(nodes, parent_id) do
          {put_child(nodes, parent_id, Map.fetch!(nodes, comment.id)), roots}
        else
          {nodes, [comment.id | roots]}
        end
      end)

    roots
    |> Enum.reverse()
    |> Enum.map(&build_node(node_map, &1, 0))
  end

  defp valid_comment?(%{id: id}) when is_binary(id), do: true
  defp valid_comment?(_comment), do: false

  defp put_child(nodes, parent_id, child) do
    update_in(nodes, [parent_id, :child_ids], &(&1 ++ [child.comment.id]))
  end

  defp build_node(node_map, id, depth) do
    node = Map.fetch!(node_map, id)
    depth = min(depth, @max_depth)

    %{
      comment: node.comment,
      depth: depth,
      children: Enum.map(node.child_ids, &build_node(node_map, &1, depth + 1))
    }
  end
end
