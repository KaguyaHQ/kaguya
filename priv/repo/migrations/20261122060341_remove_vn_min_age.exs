defmodule Kaguya.Repo.Migrations.RemoveVnMinAge do
  use Ecto.Migration

  def up do
    drop_if_exists constraint(:visual_novels, :min_age_check)

    alter table(:visual_novels) do
      remove :min_age
    end

    alter table(:vn_hist) do
      remove :min_age
    end
  end

  def down do
    alter table(:visual_novels) do
      add :min_age, :integer
    end

    alter table(:vn_hist) do
      add :min_age, :integer
    end

    create constraint(:visual_novels, :min_age_check, check: "min_age >= 0")
  end
end
