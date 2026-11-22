defmodule Kaguya.Discussions.PollOption do
  @moduledoc "One choice in a discussion post's poll."

  use Kaguya.Schema

  alias Kaguya.Discussions.Post

  schema "post_poll_options" do
    belongs_to :post, Post

    field :label, :string
    field :position, :integer

    timestamps(type: :utc_datetime)
  end
end
