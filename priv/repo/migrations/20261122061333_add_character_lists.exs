defmodule Kaguya.Repo.Migrations.AddCharacterLists do
  use Ecto.Migration

  def change do
    alter table(:lists) do
      add :item_type, :string, null: false, default: "vn"
    end

    create constraint(:lists, :lists_item_type_check, check: "item_type IN ('vn', 'character')")

    create table(:list_character_items, primary_key: false) do
      add :list_id, references(:lists, type: :binary_id, on_delete: :delete_all),
        null: false,
        primary_key: true

      add :character_id, references(:characters, type: :binary_id, on_delete: :delete_all),
        null: false,
        primary_key: true

      add :tier_id, references(:list_tiers, type: :binary_id, on_delete: :nilify_all)
      add :position, :integer, null: false
      add :tier_position, :integer

      timestamps(type: :utc_datetime)
    end

    create constraint(:list_character_items, :list_character_items_tier_position_positive_check,
             check: "tier_position IS NULL OR tier_position > 0"
           )

    create index(:list_character_items, [:list_id, :tier_id, :tier_position])
    create index(:list_character_items, [:character_id])
  end
end
