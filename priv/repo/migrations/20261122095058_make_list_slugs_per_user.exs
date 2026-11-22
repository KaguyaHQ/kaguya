defmodule Kaguya.Repo.Migrations.MakeListSlugsPerUser do
  use Ecto.Migration

  # List URLs are /@username/list/:slug, so a slug only needs to be unique per
  # owner; lists_user_id_slug_index already enforces that. The site-wide index
  # was left over from the old /lists/:slug routes.
  def up do
    drop index(:lists, [:slug], name: :lists_slug_index)
  end

  def down do
    create unique_index(:lists, [:slug], name: :lists_slug_index)
  end
end
