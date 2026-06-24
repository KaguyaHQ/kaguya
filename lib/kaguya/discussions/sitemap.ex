defmodule Kaguya.Discussions.Sitemap do
  @moduledoc false

  import Ecto.Query

  alias Kaguya.Pagination
  alias Kaguya.Characters.Character
  alias Kaguya.Discussions.Post
  alias Kaguya.Producers.Producer
  alias Kaguya.Users.User
  alias Kaguya.VisualNovels.VisualNovel

  @doc """
  Returns visible posts for sitemap indexing with the URL-relevant fields per
  category resolved in a single query. Excludes hidden and deleted posts.

  Per category, exactly one of vn_slug / producer_slug / character_slug /
  target_username is non-nil for entity categories; all are nil for standalone
  categories (general, announcements, site_discussions). The frontend uses
  category_type to pick the right URL shape.
  """
  def list_posts_for_sitemap(page \\ 1, page_size \\ 1000) do
    query =
      from(p in Post,
        left_join: vn in VisualNovel,
        on: p.category_type == ^:visual_novel and vn.id == p.entity_id,
        left_join: pr in Producer,
        on: p.category_type == ^:producer and pr.id == p.entity_id,
        left_join: ch in Character,
        on: p.category_type == ^:character and ch.id == p.entity_id,
        left_join: u in User,
        on: p.category_type == ^:user and u.id == p.entity_id,
        where:
          is_nil(p.hidden_at) and is_nil(p.deleted_at) and
            (p.category_type != ^:visual_novel or is_nil(vn.hidden_at)) and
            (p.category_type != ^:producer or is_nil(pr.hidden_at)) and
            (p.category_type != ^:character or is_nil(ch.hidden_at)) and
            (p.category_type != ^:user or not is_nil(u.username)),
        order_by: [desc: p.updated_at, desc: p.id],
        select: %{
          id: p.id,
          short_id: p.short_id,
          slug: p.slug,
          category_type: p.category_type,
          vn_slug: vn.slug,
          producer_slug: pr.slug,
          character_slug: ch.slug,
          target_username: u.username,
          updated_at: p.updated_at
        }
      )

    Pagination.paginate(query, page, page_size)
  end
end
