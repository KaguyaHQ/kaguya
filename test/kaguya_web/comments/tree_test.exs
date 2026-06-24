defmodule KaguyaWeb.Comments.TreeTest do
  use ExUnit.Case, async: true

  alias KaguyaWeb.Comments.Tree

  test "builds nested trees in flat list order" do
    root = comment("root")
    child = comment("child", root.id)
    sibling = comment("sibling")
    grandchild = comment("grandchild", child.id)

    assert [
             %{
               comment: ^root,
               depth: 0,
               children: [
                 %{comment: ^child, depth: 1, children: [%{comment: ^grandchild, depth: 2}]}
               ]
             },
             %{comment: ^sibling, depth: 0, children: []}
           ] = Tree.build([root, child, sibling, grandchild])
  end

  test "promotes orphans to roots" do
    orphan = comment("orphan", "missing-parent")

    assert [%{comment: ^orphan, depth: 0, children: []}] = Tree.build([orphan])
  end

  test "caps rendered depth" do
    comments =
      Enum.reduce(1..8, [], fn index, acc ->
        parent_id = acc |> List.last() |> then(&(&1 && &1.id))
        acc ++ [comment("comment-#{index}", parent_id)]
      end)

    deepest =
      comments
      |> Tree.build()
      |> hd()
      |> descend()

    assert deepest.depth == Tree.max_depth()
  end

  defp descend(%{children: []} = node), do: node
  defp descend(%{children: [child | _]}), do: descend(child)

  defp comment(id, parent_id \\ nil) do
    %{id: id, parent_comment_id: parent_id, content: id}
  end
end
