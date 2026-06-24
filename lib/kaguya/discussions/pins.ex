defmodule Kaguya.Discussions.Pins do
  @moduledoc false

  import Ecto.Query

  alias Kaguya.Repo
  alias Kaguya.Discussions.{Comment, Post}

  @max_pinned_posts 6

  def ensure_post_pin_capacity(%{is_pinned: true}, category_type) do
    count =
      from(t in Post, where: t.is_pinned == true and t.category_type == ^category_type)
      |> Repo.aggregate(:count)

    if count >= @max_pinned_posts do
      unpin_oldest_post(category_type)

      new_count =
        from(t in Post, where: t.is_pinned == true and t.category_type == ^category_type)
        |> Repo.aggregate(:count)

      if new_count >= @max_pinned_posts,
        do: {:error, "Maximum pinned posts (#{@max_pinned_posts}) reached for this category."},
        else: :ok
    else
      :ok
    end
  end

  def ensure_post_pin_capacity(_attrs, _category_type), do: :ok

  def ensure_top_level_comment_pin(%Comment{parent_comment_id: nil}, _attrs), do: :ok

  def ensure_top_level_comment_pin(_comment, %{is_pinned: true}),
    do: {:error, "Only top-level comments can be pinned"}

  def ensure_top_level_comment_pin(_comment, _attrs), do: :ok

  def check_comment_not_hidden_for_pin(%Comment{hidden_at: nil}, _attrs), do: :ok

  def check_comment_not_hidden_for_pin(_comment, %{is_pinned: true}),
    do: {:error, "Hidden comments cannot be pinned"}

  def check_comment_not_hidden_for_pin(_comment, _attrs), do: :ok

  defp unpin_oldest_post(category_type) do
    case Repo.one(
           from(t in Post,
             where: t.is_pinned == true and t.category_type == ^category_type,
             order_by: [asc: t.inserted_at],
             limit: 1,
             select: t.id
           )
         ) do
      nil ->
        :ok

      id ->
        Repo.update_all(
          from(t in Post, where: t.id == ^id),
          set: [is_pinned: false]
        )
    end
  end
end
