defmodule Kaguya.Characters.Quotes do
  @moduledoc """
  Reads and writes for character quotes — listing, creating, deleting,
  and like/unlike.

  Lives under `Kaguya.Characters` because the data (`Quote`, `QuoteLike`,
  `QuoteFavorite`) belongs to the characters domain. Previously these lived
  inside `Kaguya.VisualNovels`, which violated context boundaries — the VN
  context was directly mutating Characters tables.
  """

  import Ecto.Query

  alias Kaguya.Activities
  alias Kaguya.Characters.{Quote, QuoteFavorite, QuoteLike, VNCharacter}
  alias Kaguya.Repo
  alias Kaguya.Utils.TextPreview

  @doc """
  Lists quotes for a visual novel, ordered by likes then score.
  Accepts optional `user_id` to populate `liked_by_me` and
  `favorited_by_me` (the inline bookmark state on quote cards).
  """
  def list_quotes_for_vn(visual_novel_id, opts \\ []) do
    user_id = Keyword.get(opts, :user_id)

    Quote
    |> where([q], q.visual_novel_id == ^visual_novel_id)
    |> join_viewer_state(user_id)
    |> order_by([q], desc: q.likes_count, desc: q.score)
    |> preload(:character)
    |> Repo.all()
  end

  @doc """
  Lists quotes for a character, ordered by likes then score.
  Accepts optional `user_id` to populate `liked_by_me` and
  `favorited_by_me`.
  """
  def list_quotes_for_character(character_id, opts \\ []) do
    user_id = Keyword.get(opts, :user_id)

    Quote
    |> where([q], q.character_id == ^character_id)
    |> join_viewer_state(user_id)
    |> order_by([q], desc: q.likes_count, desc: q.score)
    |> preload(:visual_novel)
    |> Repo.all()
  end

  # Attaches both `liked_by_me` and `favorited_by_me` virtuals from the
  # viewer's QuoteLike / QuoteFavorite rows. Anonymous viewers get the
  # query untouched (both virtuals stay at their `false` defaults).
  defp join_viewer_state(query, nil), do: query

  defp join_viewer_state(query, user_id) do
    query
    |> join(:left, [q], l in QuoteLike, on: l.vn_quote_id == q.id and l.user_id == ^user_id)
    |> join(:left, [q, _l], f in QuoteFavorite,
      on: f.vn_quote_id == q.id and f.user_id == ^user_id
    )
    |> select_merge([q, l, f], %{
      liked_by_me: not is_nil(l.user_id),
      favorited_by_me: not is_nil(f.user_id)
    })
  end

  @doc """
  Creates a user-submitted quote.
  """
  def create_quote(attrs) do
    with :ok <- validate_character_in_vn(attrs),
         {:ok, quote} <- %Quote{} |> Quote.changeset(attrs) |> Repo.insert() do
      record_added_quote_activity(quote)
      {:ok, Repo.preload(quote, [:character, :visual_novel, :creator])}
    end
  end

  defp record_added_quote_activity(quote) do
    Activities.record_activity(%{
      user_id: quote.created_by,
      action: :added_quote,
      entity_type: "quote",
      entity_id: quote.id,
      metadata: %{
        quote_text_preview: TextPreview.truncate_on_words(quote.quote),
        vn_id: quote.visual_novel_id,
        character_id: quote.character_id
      }
    })
  end

  defp validate_character_in_vn(%{character_id: cid, visual_novel_id: vn_id})
       when not is_nil(cid) and not is_nil(vn_id) do
    if Repo.exists?(
         from vc in VNCharacter,
           where: vc.character_id == ^cid and vc.visual_novel_id == ^vn_id
       ) do
      :ok
    else
      {:error, "Character does not appear in this visual novel"}
    end
  end

  defp validate_character_in_vn(_attrs), do: :ok

  @doc """
  Deletes a quote (mod/admin only). Removes all `:added_quote` / `:liked_quote`
  activity rows pointing at this quote so the feed doesn't display orphans.
  """
  def delete_quote(quote_id) do
    case Repo.get(Quote, quote_id) do
      nil ->
        {:error, "Quote not found"}

      quote ->
        with {:ok, deleted} <- Repo.delete(quote) do
          Activities.delete_activities_for_entity("quote", quote_id)
          {:ok, deleted}
        end
    end
  end

  @doc """
  Like a quote. Idempotent — re-liking is a no-op.
  """
  def like_quote(quote_id, user_id) do
    Repo.transact(fn ->
      case Repo.get(Quote, quote_id) do
        nil ->
          {:error, "Quote not found"}

        quote ->
          now = DateTime.utc_now() |> DateTime.truncate(:second)

          {count, _} =
            Repo.insert_all(
              QuoteLike,
              [%{user_id: user_id, vn_quote_id: quote_id, inserted_at: now}],
              on_conflict: :nothing,
              conflict_target: [:user_id, :vn_quote_id]
            )

          if count > 0 do
            from(q in Quote, where: q.id == ^quote_id)
            |> Repo.update_all(inc: [likes_count: 1])

            record_liked_quote_activity(user_id, quote)
          end

          {:ok, true}
      end
    end)
  end

  defp record_liked_quote_activity(user_id, quote) do
    Activities.record_activity(%{
      user_id: user_id,
      action: :liked_quote,
      entity_type: "quote",
      entity_id: quote.id,
      metadata: %{
        quote_text_preview: TextPreview.truncate_on_words(quote.quote),
        quote_author_id: quote.created_by,
        vn_id: quote.visual_novel_id,
        character_id: quote.character_id
      }
    })
  end

  @doc """
  Unlike a quote. Idempotent — unliking when not liked is a no-op.
  """
  def unlike_quote(quote_id, user_id) do
    Repo.transact(fn ->
      case Repo.get_by(QuoteLike, user_id: user_id, vn_quote_id: quote_id) do
        nil ->
          {:ok, true}

        like ->
          Repo.delete!(like)

          from(q in Quote, where: q.id == ^quote_id and q.likes_count > 0)
          |> Repo.update_all(inc: [likes_count: -1])

          Activities.delete_activity(user_id, :liked_quote, "quote", quote_id)

          {:ok, true}
      end
    end)
  end
end
