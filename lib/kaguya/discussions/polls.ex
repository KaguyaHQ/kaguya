defmodule Kaguya.Discussions.Polls do
  @moduledoc """
  Single-choice polls on discussion posts. A post has a poll when it has
  options; people get one vote each and can change it.
  """

  import Ecto.Query

  alias Kaguya.Discussions.{PollOption, PollVote, Post, Posts}
  alias Kaguya.Repo

  @min_options 2
  @max_options 6
  @max_label_length 80

  def min_options, do: @min_options
  def max_options, do: @max_options
  def max_label_length, do: @max_label_length

  @doc """
  Trims labels and drops blank ones. Returns `{:ok, labels}` when 2–6
  distinct labels remain, or `{:error, message}`.
  """
  def normalize_options(labels) when is_list(labels) do
    labels =
      labels
      |> Enum.map(&(&1 |> to_string() |> String.trim()))
      |> Enum.reject(&(&1 == ""))

    cond do
      length(labels) < @min_options ->
        {:error, "A poll needs at least #{@min_options} options"}

      length(labels) > @max_options ->
        {:error, "A poll can have at most #{@max_options} options"}

      Enum.any?(labels, &(String.length(&1) > @max_label_length)) ->
        {:error, "Poll options must be #{@max_label_length} characters or fewer"}

      labels |> Enum.uniq_by(&String.downcase/1) |> length() != length(labels) ->
        {:error, "Poll options must be different"}

      true ->
        {:ok, labels}
    end
  end

  def normalize_options(_labels), do: {:error, "A poll needs at least #{@min_options} options"}

  @doc "Adds a poll to `post`. Call inside the post's creation transaction."
  def create_poll(%Post{id: post_id}, labels) do
    with {:ok, labels} <- normalize_options(labels) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      rows =
        labels
        |> Enum.with_index()
        |> Enum.map(fn {label, position} ->
          %{
            id: UUIDv7.generate(),
            post_id: post_id,
            label: label,
            position: position,
            inserted_at: now,
            updated_at: now
          }
        end)

      {count, _} = Repo.insert_all(PollOption, rows)
      {:ok, count}
    end
  end

  @doc """
  Records `user_id`'s vote, replacing any earlier one. Returns the updated
  poll as `poll_for/2` shapes it.
  """
  def vote(post_id, option_id, user_id) do
    with {:ok, option_id} <- cast_id(option_id),
         {:ok, post_id} <- cast_id(post_id),
         {:ok, post} <- Posts.get_post_for_viewer(post_id, user_id),
         :ok <- open_for_votes(post),
         true <- option_in_post?(option_id, post.id) || {:error, :not_found} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Repo.insert_all(
        PollVote,
        [
          %{
            post_id: post.id,
            user_id: user_id,
            option_id: option_id,
            inserted_at: now,
            updated_at: now
          }
        ],
        on_conflict: {:replace, [:option_id, :updated_at]},
        conflict_target: [:post_id, :user_id]
      )

      {:ok, poll_for(post.id, user_id)}
    end
  end

  @doc "The poll on `post_id` for `viewer_id`, or nil when the post has none."
  def poll_for(post_id, viewer_id), do: Map.get(polls_by_post_ids([post_id], viewer_id), post_id)

  @doc """
  Polls for `post_ids`, keyed by post id; posts without a poll are absent.
  Each poll is `%{options: [%{id, label, votes}], total_votes, my_option_id}`.
  """
  def polls_by_post_ids([], _viewer_id), do: %{}

  def polls_by_post_ids(post_ids, viewer_id) do
    options =
      Repo.all(
        from o in PollOption,
          where: o.post_id in ^post_ids,
          order_by: [asc: o.post_id, asc: o.position]
      )

    if options == [], do: %{}, else: build_polls(options, post_ids, viewer_id)
  end

  defp build_polls(options, post_ids, viewer_id) do
    counts =
      Repo.all(
        from v in PollVote,
          where: v.post_id in ^post_ids,
          group_by: v.option_id,
          select: {v.option_id, count()}
      )
      |> Map.new()

    mine = my_votes(post_ids, viewer_id)

    options
    |> Enum.group_by(& &1.post_id)
    |> Map.new(fn {post_id, post_options} ->
      options =
        Enum.map(post_options, &%{id: &1.id, label: &1.label, votes: Map.get(counts, &1.id, 0)})

      {post_id,
       %{
         options: options,
         total_votes: options |> Enum.map(& &1.votes) |> Enum.sum(),
         my_option_id: Map.get(mine, post_id)
       }}
    end)
  end

  defp my_votes(_post_ids, nil), do: %{}

  defp my_votes(post_ids, viewer_id) do
    Repo.all(
      from v in PollVote,
        where: v.post_id in ^post_ids and v.user_id == ^viewer_id,
        select: {v.post_id, v.option_id}
    )
    |> Map.new()
  end

  defp open_for_votes(%Post{is_locked: true}), do: {:error, :locked}

  defp open_for_votes(%Post{hidden_at: hidden_at}) when not is_nil(hidden_at),
    do: {:error, :locked}

  defp open_for_votes(%Post{deleted_at: deleted_at}) when not is_nil(deleted_at),
    do: {:error, :locked}

  defp open_for_votes(_post), do: :ok

  defp option_in_post?(option_id, post_id) do
    Repo.exists?(from o in PollOption, where: o.id == ^option_id and o.post_id == ^post_id)
  end

  defp cast_id(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :not_found}
    end
  end
end
