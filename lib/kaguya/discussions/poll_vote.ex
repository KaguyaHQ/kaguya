defmodule Kaguya.Discussions.PollVote do
  @moduledoc "A person's single vote in a post's poll."

  use Kaguya.Schema

  alias Kaguya.Discussions.{PollOption, Post}
  alias Kaguya.Users.User

  @primary_key false

  schema "post_poll_votes" do
    belongs_to :post, Post, primary_key: true
    belongs_to :user, User, primary_key: true
    belongs_to :option, PollOption

    timestamps(type: :utc_datetime)
  end
end
