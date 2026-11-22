defmodule Kaguya.Discussions.PollsTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Kaguya.Discussions
  alias Kaguya.Discussions.{PollOption, Polls, Post}
  alias Kaguya.Repo
  alias Kaguya.Test.UserFixtures

  setup do
    :ok = Sandbox.checkout(Repo)
    %{author: UserFixtures.insert_user!()}
  end

  defp create_poll_post(author, options) do
    Discussions.create_post(author.id, %{
      title: "Best Key VN?",
      content: "Vote below.",
      category_type: :general,
      poll_options: options
    })
  end

  defp option_ids(post_id) do
    Repo.all(
      from o in PollOption, where: o.post_id == ^post_id, order_by: o.position, select: o.id
    )
  end

  describe "normalize_options/1" do
    test "trims labels and drops blank ones" do
      assert Polls.normalize_options([" Clannad ", "", "  ", "Air"]) == {:ok, ["Clannad", "Air"]}
    end

    test "rejects too few, too many, too long and duplicate options" do
      assert {:error, _} = Polls.normalize_options(["Only one", ""])
      assert {:error, _} = Polls.normalize_options(Enum.map(1..7, &"Option #{&1}"))
      assert {:error, _} = Polls.normalize_options(["ok", String.duplicate("x", 81)])
      assert {:error, _} = Polls.normalize_options(["Kanon", "kanon"])
    end
  end

  test "creating a post with options adds the poll in order", %{author: author} do
    {:ok, post} = create_poll_post(author, ["Clannad", "Air", "Kanon"])

    poll = Discussions.poll_for(post.id, author.id)

    assert Enum.map(poll.options, & &1.label) == ["Clannad", "Air", "Kanon"]
    assert poll.total_votes == 0
    assert poll.my_option_id == nil
  end

  test "invalid options fail the whole post", %{author: author} do
    assert {:error, _message} = create_poll_post(author, ["Just one"])
    refute Repo.exists?(from p in Post, where: p.title == "Best Key VN?")
  end

  test "posts without options have no poll", %{author: author} do
    {:ok, post} =
      Discussions.create_post(author.id, %{
        title: "No poll here",
        content: "Just text.",
        category_type: :general
      })

    assert Discussions.poll_for(post.id, author.id) == nil
  end

  test "votes count once per person and can be changed", %{author: author} do
    voter = UserFixtures.insert_user!()
    {:ok, post} = create_poll_post(author, ["Clannad", "Air"])
    [clannad, air] = option_ids(post.id)

    assert {:ok, poll} = Discussions.vote_poll(post.id, clannad, voter.id)
    assert poll.my_option_id == clannad
    assert poll.total_votes == 1

    assert {:ok, poll} = Discussions.vote_poll(post.id, air, voter.id)
    assert poll.my_option_id == air
    assert poll.total_votes == 1
    assert Enum.map(poll.options, & &1.votes) == [0, 1]

    {:ok, _poll} = Discussions.vote_poll(post.id, clannad, author.id)
    polls = Discussions.polls_by_post_ids([post.id], nil)
    assert polls[post.id].total_votes == 2
    assert polls[post.id].my_option_id == nil
  end

  test "rejects votes on locked posts and options from other polls", %{author: author} do
    voter = UserFixtures.insert_user!()
    {:ok, post} = create_poll_post(author, ["Clannad", "Air"])
    {:ok, other} = create_poll_post(author, ["Kanon", "Rewrite"])
    [other_option | _] = option_ids(other.id)
    [option | _] = option_ids(post.id)

    assert {:error, :not_found} = Discussions.vote_poll(post.id, other_option, voter.id)
    assert {:error, :not_found} = Discussions.vote_poll(post.id, "not-a-uuid", voter.id)
    assert {:error, :not_found} = Discussions.vote_poll("not-a-uuid", option, voter.id)

    Repo.update_all(from(p in Post, where: p.id == ^post.id), set: [is_locked: true])
    assert {:error, :locked} = Discussions.vote_poll(post.id, option, voter.id)
  end
end
