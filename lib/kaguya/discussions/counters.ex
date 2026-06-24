defmodule Kaguya.Discussions.Counters do
  @moduledoc false

  import Ecto.Query

  alias Kaguya.Repo
  alias Kaguya.Discussions.{Comment, Post}

  def recalculate_last_comment(post_id) do
    last =
      from(c in Comment,
        where: c.post_id == ^post_id and is_nil(c.hidden_at) and is_nil(c.deleted_at),
        order_by: [desc: c.inserted_at],
        limit: 1,
        select: %{user_id: c.user_id, inserted_at: c.inserted_at}
      )
      |> Repo.one()

    {last_at, last_uid} =
      case last do
        nil -> {nil, nil}
        %{inserted_at: at, user_id: uid} -> {at, uid}
      end

    Repo.update_all(
      from(t in Post, where: t.id == ^post_id),
      set: [last_comment_at: last_at, last_comment_user_id: last_uid]
    )
  end
end
