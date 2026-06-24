defmodule Mix.Tasks.Kaguya.ExplainRecommendations do
  @moduledoc """
  Inspect a user's personalized VN recommendations.

  Prints the top-K recs with their EASE score and the "because you liked"
  attribution items including the user's actual rating on each source.
  Handy for eyeballing model quality.

  Usage:
      mix kaguya.explain_recommendations --user USERNAME
      mix kaguya.explain_recommendations --user USERNAME --limit 30
  """
  use Mix.Task

  @requirements ["app.start"]
  @shortdoc "Show a user's top VN recommendations"

  import Ecto.Query
  alias Kaguya.Repo
  alias Kaguya.Recommendations.UserVnRecommendation
  alias Kaguya.Reviews.Rating
  alias Kaguya.Users.User
  alias Kaguya.VisualNovels.VisualNovel

  @impl Mix.Task
  def run(argv) do
    {opts, _, _} =
      OptionParser.parse(argv, strict: [user: :string, limit: :integer])

    username = opts |> Keyword.fetch!(:user) |> String.trim_leading("@")
    limit = Keyword.get(opts, :limit, 20)

    user_id =
      Repo.one(from(u in User, where: u.username == ^username, select: u.id)) ||
        Mix.raise("No user with username #{username}")

    recs = fetch_recs(user_id, limit)
    print_recs(username, user_id, recs)
  end

  defp fetch_recs(user_id, limit) do
    from(r in UserVnRecommendation,
      where: r.user_id == ^user_id,
      order_by: [asc: r.rank],
      limit: ^limit,
      preload: [:visual_novel]
    )
    |> Repo.all()
  end

  defp print_recs(username, _user_id, []) do
    IO.puts("No recommendations yet for @#{username}.")
    IO.puts("Run: mix kaguya.generate_recommendations --user #{username}")
  end

  defp print_recs(username, user_id, recs) do
    {vn_by_id, rating_by_vn_id} = load_context(user_id, recs)

    IO.puts("")

    IO.puts(
      "=== recs for @#{username} (#{length(recs)} rows, model: #{hd(recs).model_version}) ==="
    )

    IO.puts("generated at #{hd(recs).generated_at}")
    IO.puts("")

    Enum.each(recs, &print_rec(&1, vn_by_id, rating_by_vn_id))
  end

  defp print_rec(rec, vn_by_id, rating_by_vn_id) do
    IO.puts(
      "#{pad(rec.rank, 3)}. " <>
        String.pad_trailing(String.slice(rec.visual_novel.title, 0, 45), 46) <>
        " ease=#{Float.round(rec.ease_score, 3)}"
    )

    total_positive = rec.total_positive_contribution

    rec.reasons
    |> Enum.flat_map(fn reason ->
      case Map.get(vn_by_id, reason["visual_novel_id"]) do
        nil -> []
        vn -> [{vn, reason["contribution"]}]
      end
    end)
    |> Enum.each(fn {rvn, contribution} ->
      val_str =
        case Map.get(rating_by_vn_id, rvn.id) do
          nil -> ""
          v -> " (rated #{Float.round(v, 1)})"
        end

      pct_str =
        if is_number(contribution) and is_number(total_positive) and total_positive > 0 do
          " [#{round(contribution / total_positive * 100)}%]"
        else
          ""
        end

      IO.puts("       ↳ because you liked: #{String.slice(rvn.title, 0, 50)}#{val_str}#{pct_str}")
    end)

    IO.puts("")
  end

  defp load_context(user_id, recs) do
    reason_ids =
      recs
      |> Enum.flat_map(fn rec -> Enum.map(rec.reasons, & &1["visual_novel_id"]) end)
      |> Enum.uniq()

    {lookup_vns(reason_ids), lookup_ratings(user_id, reason_ids)}
  end

  defp lookup_vns([]), do: %{}

  defp lookup_vns(ids) do
    from(vn in VisualNovel, where: vn.id in ^ids, select: {vn.id, vn})
    |> Repo.all()
    |> Map.new()
  end

  defp lookup_ratings(_user_id, []), do: %{}

  defp lookup_ratings(user_id, vn_ids) do
    # 1-10 scale to match the pipeline's encoding.
    from(r in Rating,
      where: r.user_id == ^user_id,
      where: r.visual_novel_id in ^vn_ids,
      select: {r.visual_novel_id, r.rating * 2.0}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp pad(n, w), do: n |> Integer.to_string() |> String.pad_leading(w)
end
