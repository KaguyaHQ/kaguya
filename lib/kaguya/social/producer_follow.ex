defmodule Kaguya.Social.ProducerFollow do
  use Ecto.Schema
  import Ecto.Changeset

  alias Kaguya.Users.User
  alias Kaguya.Producers.Producer

  @primary_key false
  @foreign_key_type :binary_id
  schema "producer_follows" do
    belongs_to :follower, User, primary_key: true
    belongs_to :producer, Producer, primary_key: true

    timestamps(type: :utc_datetime)
  end

  def changeset(producer_follow, attrs) do
    producer_follow
    |> cast(attrs, [:follower_id, :producer_id])
    |> validate_required([:follower_id, :producer_id])
    |> unique_constraint([:follower_id, :producer_id],
      name: :producer_follows_pkey,
      message: "You are already following this producer"
    )
  end
end
