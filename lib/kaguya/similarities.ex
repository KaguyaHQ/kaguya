defmodule Kaguya.Similarities do
  @moduledoc """
  Context for community-driven VN similarity voting.
  All mutations are idempotent.
  """

  import Ecto.Query

  alias Kaguya.{Activities, Repo, VisualNovels}
  alias Kaguya.VisualNovels.VisualNovel
  alias Kaguya.Similarities.{Similarity, SimilarityVote}

  @doc """
  Creates a VN similarity relationship with initial upvote.
  Idempotent: if similarity exists, just ensures user has upvoted it.
  """
  def create_vn_similarity(vn_id, similar_vn_id, user_id) do
    {low_id, high_id} = normalize_vn_ids(vn_id, similar_vn_id)

    Repo.transact(fn ->
      # Ensure similarity exists
      _similarity = get_or_create_similarity(low_id, high_id)

      # Ensure user has upvoted
      set_vote(low_id, high_id, user_id, 1)

      # Record activity (idempotent via on_conflict: :nothing)
      record_similarity_activity(user_id, vn_id, similar_vn_id)

      {:ok, true}
    end)
  end

  @doc """
  Upvotes a VN similarity by a user.
  Idempotent: no-op if already upvoted, switches if downvoted.
  """
  def upvote_vn_similarity(vn_id, similar_vn_id, user_id) do
    {low_id, high_id} = normalize_vn_ids(vn_id, similar_vn_id)

    Repo.transact(fn ->
      case get_similarity(low_id, high_id) do
        nil ->
          {:error, "Similarity does not exist"}

        _similarity ->
          set_vote(low_id, high_id, user_id, 1)
          {:ok, true}
      end
    end)
  end

  @doc """
  Downvotes a VN similarity by a user.
  Idempotent: no-op if already downvoted, switches if upvoted.
  """
  def downvote_vn_similarity(vn_id, similar_vn_id, user_id) do
    {low_id, high_id} = normalize_vn_ids(vn_id, similar_vn_id)

    Repo.transact(fn ->
      case get_similarity(low_id, high_id) do
        nil ->
          {:error, "Similarity does not exist"}

        _similarity ->
          set_vote(low_id, high_id, user_id, -1)
          {:ok, true}
      end
    end)
  end

  @doc """
  Clears any existing vote for a VN similarity by a user.
  Idempotent: no-op if no vote exists.
  """
  def clear_vn_similarity_vote(vn_id, similar_vn_id, user_id) do
    {low_id, high_id} = normalize_vn_ids(vn_id, similar_vn_id)

    Repo.transact(fn ->
      case get_vote(low_id, high_id, user_id) do
        nil ->
          {:ok, true}

        vote ->
          delete_vote(vote, low_id, high_id)
          {:ok, true}
      end
    end)
  end

  @doc """
  Lists similar VNs for a visual novel with vote counts and user's vote status.
  Queries bidirectionally since similarities are stored in normalized order.
  """
  def list_similar_vns_with_votes(%VisualNovel{} = vn, opts \\ []) do
    user_id = Keyword.get(opts, :user_id)
    limit = Keyword.get(opts, :limit, 10)
    allowed = Keyword.get(opts, :allowed_categories)

    query1 =
      from vs in Similarity,
        where: vs.visual_novel_id == ^vn.id,
        select: %{
          similar_vn_id: vs.similar_vn_id,
          net_votes: vs.upvotes_count - vs.downvotes_count,
          score: vs.score,
          normalized_vn_id: vs.visual_novel_id,
          normalized_similar_vn_id: vs.similar_vn_id
        }

    query2 =
      from vs in Similarity,
        where: vs.similar_vn_id == ^vn.id,
        select: %{
          similar_vn_id: vs.visual_novel_id,
          net_votes: vs.upvotes_count - vs.downvotes_count,
          score: vs.score,
          normalized_vn_id: vs.visual_novel_id,
          normalized_similar_vn_id: vs.similar_vn_id
        }

    base_query = union_all(query1, ^query2)

    query =
      if user_id do
        from q in subquery(base_query),
          join: v in VisualNovel,
          on: v.id == q.similar_vn_id,
          left_join: vsv in SimilarityVote,
          on:
            vsv.visual_novel_id == q.normalized_vn_id and
              vsv.similar_vn_id == q.normalized_similar_vn_id and
              vsv.user_id == ^user_id,
          select: %{
            visual_novel: v,
            net_votes: q.net_votes,
            user_vote: vsv.vote_value
          },
          order_by: [desc: q.net_votes, desc: q.score],
          limit: ^limit
      else
        from q in subquery(base_query),
          join: v in VisualNovel,
          on: v.id == q.similar_vn_id,
          select: %{
            visual_novel: v,
            net_votes: q.net_votes,
            user_vote: fragment("NULL")
          },
          order_by: [desc: q.net_votes, desc: q.score],
          limit: ^limit
      end

    query = if allowed, do: where(query, [_q, v], v.title_category in ^allowed), else: query

    # AVN segregation: JP VNs only see JP, AVNs only see AVNs
    query = where(query, [_q, v], v.is_avn == ^vn.is_avn)

    {:ok, Repo.all(query)}
  end

  @doc """
  A user's own similarity votes for every pair involving `vn`, keyed by the
  *other* VN's id (i.e. the `similar_vn_id` as seen from `vn`'s perspective).

  This is the viewer-specific overlay that `list_similar_vns_with_votes/2`
  folds into each row's `:user_vote`. It lives apart so the recommendations
  list can be computed viewer-independently (and cached) while the per-user
  highlights hydrate separately. Pairs are stored normalized (`min`,`max`),
  so we map each row back to whichever side isn't `vn`.
  """
  def user_votes_for_vn(%VisualNovel{id: vn_id}, user_id) do
    from(v in SimilarityVote,
      where:
        v.user_id == ^user_id and
          (v.visual_novel_id == ^vn_id or v.similar_vn_id == ^vn_id),
      select: {v.visual_novel_id, v.similar_vn_id, v.vote_value}
    )
    |> Repo.all()
    |> Map.new(fn {low, high, vote} ->
      {if(low == vn_id, do: high, else: low), vote}
    end)
  end

  # ──────────────────────────
  # Private helpers
  # ──────────────────────────

  defp normalize_vn_ids(a, b), do: {min(a, b), max(a, b)}

  defp get_similarity(low_id, high_id) do
    Repo.get_by(Similarity, visual_novel_id: low_id, similar_vn_id: high_id)
  end

  defp get_or_create_similarity(low_id, high_id) do
    case get_similarity(low_id, high_id) do
      nil ->
        %Similarity{}
        |> Similarity.changeset(%{
          visual_novel_id: low_id,
          similar_vn_id: high_id,
          upvotes_count: 0,
          downvotes_count: 0
        })
        |> Repo.insert!()

      existing ->
        existing
    end
  end

  defp get_vote(low_id, high_id, user_id) do
    Repo.get_by(SimilarityVote,
      visual_novel_id: low_id,
      similar_vn_id: high_id,
      user_id: user_id
    )
  end

  defp set_vote(low_id, high_id, user_id, new_value) do
    case get_vote(low_id, high_id, user_id) do
      nil ->
        # Create new vote
        %SimilarityVote{}
        |> SimilarityVote.changeset(%{
          visual_novel_id: low_id,
          similar_vn_id: high_id,
          user_id: user_id,
          vote_value: new_value
        })
        |> Repo.insert!()

        increment_vote_count(low_id, high_id, new_value)

      %SimilarityVote{vote_value: ^new_value} ->
        # Already has this vote, no-op
        :ok

      existing ->
        # Switch vote
        old_value = existing.vote_value

        existing
        |> SimilarityVote.changeset(%{vote_value: new_value})
        |> Repo.update!()

        decrement_vote_count(low_id, high_id, old_value)
        increment_vote_count(low_id, high_id, new_value)
    end
  end

  defp delete_vote(vote, low_id, high_id) do
    old_value = vote.vote_value
    Repo.delete!(vote)
    decrement_vote_count(low_id, high_id, old_value)
  end

  defp increment_vote_count(low_id, high_id, 1) do
    from(vs in Similarity,
      where: vs.visual_novel_id == ^low_id and vs.similar_vn_id == ^high_id,
      update: [inc: [upvotes_count: 1]]
    )
    |> Repo.update_all([])
  end

  defp increment_vote_count(low_id, high_id, -1) do
    from(vs in Similarity,
      where: vs.visual_novel_id == ^low_id and vs.similar_vn_id == ^high_id,
      update: [inc: [downvotes_count: 1]]
    )
    |> Repo.update_all([])
  end

  defp decrement_vote_count(low_id, high_id, 1) do
    from(vs in Similarity,
      where: vs.visual_novel_id == ^low_id and vs.similar_vn_id == ^high_id,
      update: [inc: [upvotes_count: -1]]
    )
    |> Repo.update_all([])
  end

  defp decrement_vote_count(low_id, high_id, -1) do
    from(vs in Similarity,
      where: vs.visual_novel_id == ^low_id and vs.similar_vn_id == ^high_id,
      update: [inc: [downvotes_count: -1]]
    )
    |> Repo.update_all([])
  end

  # ──────────────────────────
  # Activity recording
  # ──────────────────────────

  defp record_similarity_activity(user_id, vn_id, similar_vn_id) do
    source_vn = VisualNovels.get_visual_novel(vn_id)
    similar_vn = VisualNovels.get_visual_novel(similar_vn_id)

    if source_vn && similar_vn do
      Activities.record_activity(%{
        user_id: user_id,
        action: :recommended_similar,
        entity_type: "similarity",
        # entity_id is similar_vn_id (same pattern as shelves using vn_id for composite PKs).
        # Constraint [user_id, action, entity_type, entity_id] deduplicates per user per similar VN.
        entity_id: similar_vn_id,
        metadata:
          Map.merge(
            vn_metadata(source_vn, "source"),
            vn_metadata(similar_vn, "similar")
          )
      })
    end
  end

  defp vn_metadata(vn, prefix) do
    %{
      "#{prefix}_vn_id" => vn.id,
      "#{prefix}_vn_title" => vn.title,
      "#{prefix}_vn_slug" => vn.slug,
      "#{prefix}_vn_image_url" => VisualNovels.build_image_urls(vn)[:small],
      "#{prefix}_vn_release_year" => release_year(vn.release_date)
    }
  end

  defp release_year(%Date{year: y}), do: y
  defp release_year(_), do: nil
end
