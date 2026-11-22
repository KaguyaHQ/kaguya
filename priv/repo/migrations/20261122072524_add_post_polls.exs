defmodule Kaguya.Repo.Migrations.AddPostPolls do
  use Ecto.Migration

  def change do
    # A post has a poll when it has options.
    create table(:post_poll_options, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :post_id, references(:posts, type: :uuid, on_delete: :delete_all), null: false
      add :label, :string, null: false
      add :position, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:post_poll_options, [:post_id, :position])

    # One vote per person per poll; changing a vote replaces `option_id`.
    create table(:post_poll_votes, primary_key: false) do
      add :post_id, references(:posts, type: :uuid, on_delete: :delete_all),
        null: false,
        primary_key: true

      add :user_id, references(:users, type: :uuid, on_delete: :delete_all),
        null: false,
        primary_key: true

      add :option_id, references(:post_poll_options, type: :uuid, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime)
    end

    create index(:post_poll_votes, [:option_id])
  end
end
