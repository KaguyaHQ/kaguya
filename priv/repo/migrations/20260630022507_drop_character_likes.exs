defmodule Kaguya.Repo.Migrations.DropCharacterLikes do
  use Ecto.Migration

  def up do
    drop table(:character_likes)
    drop_if_exists index(:characters, [:likes_count])

    alter table(:characters) do
      remove :likes_count
    end
  end

  def down do
    alter table(:characters) do
      add :likes_count, :integer, default: 0, null: false
    end

    create index(:characters, [:likes_count])

    create table(:character_likes, primary_key: false) do
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all),
        primary_key: true,
        null: false

      add :character_id, references(:characters, type: :uuid, on_delete: :delete_all),
        primary_key: true,
        null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:character_likes, [:character_id])
  end
end
