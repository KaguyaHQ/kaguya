defmodule Kaguya.Discussions.Category do
  @moduledoc """
  Category configuration for the discussions system.
  Category metadata is defined at compile time — no DB table needed.
  """

  @category_types [
    :general,
    :announcements,
    :site_discussions,
    :visual_novel,
    :producer,
    :character,
    :user
  ]

  @categories %{
    general: %{
      name: "General",
      slug: "general",
      description: "General visual novel discussion",
      position: 1,
      admin_only: false,
      entity: false
    },
    announcements: %{
      name: "Announcements",
      slug: "announcements",
      description: "Site announcements and updates",
      position: 2,
      admin_only: true,
      entity: false
    },
    site_discussions: %{
      name: "Feedback",
      slug: "feedback",
      description: "Bug reports, feature requests, and site feedback",
      position: 3,
      admin_only: false,
      entity: false
    },
    visual_novel: %{
      name: "Visual Novels",
      slug: "visual-novels",
      description: "Discussions about specific visual novels",
      position: 4,
      admin_only: false,
      entity: true
    },
    producer: %{
      name: "Producers",
      slug: "producers",
      description: "Discussions about specific producers",
      position: 5,
      admin_only: false,
      entity: true
    },
    character: %{
      name: "Characters",
      slug: "characters",
      description: "Discussions about specific characters",
      position: 6,
      admin_only: false,
      entity: true
    },
    user: %{
      name: "Users",
      slug: "users",
      description: "Discussions with or about specific users",
      position: 7,
      admin_only: false,
      entity: true
    }
  }

  def category_types, do: @category_types

  def categories, do: @categories

  def get(category_type) when is_atom(category_type), do: Map.get(@categories, category_type)
  def get(_), do: nil

  def entity_category?(category_type), do: get_in(@categories, [category_type, :entity]) == true

  def admin_only?(category_type), do: get_in(@categories, [category_type, :admin_only]) == true

  def standalone_categories do
    @categories
    |> Enum.filter(fn {_k, v} -> !v.entity end)
    |> Enum.sort_by(fn {_k, v} -> v.position end)
  end

  def entity_categories do
    @categories
    |> Enum.filter(fn {_k, v} -> v.entity end)
    |> Enum.sort_by(fn {_k, v} -> v.position end)
  end
end
