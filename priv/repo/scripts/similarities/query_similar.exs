# Usage: mix run priv/repo/scripts/similarities/query_similar.exs "Fata Morgana"
# Usage: mix run priv/repo/scripts/similarities/query_similar.exs v2016
# Usage: mix run priv/repo/scripts/similarities/query_similar.exs --slug henpri-hentai-prison

Logger.configure(level: :warning)

import Ecto.Query
alias Kaguya.Repo
alias Kaguya.VisualNovels.VisualNovel
alias Kaguya.Similarities.Similarity

search = System.argv() |> List.last()

# Find the VN
vn =
  cond do
    String.starts_with?(search, "v") and String.match?(search, ~r/^v\d+$/) ->
      Repo.one(from v in VisualNovel, where: v.vndb_id == ^search)

    String.starts_with?(search, "--slug") ->
      slug = System.argv() |> Enum.at(-1)
      Repo.one(from v in VisualNovel, where: v.slug == ^slug)

    true ->
      term = "%#{search}%"

      Repo.one(
        from v in VisualNovel,
          where: ilike(v.title, ^term),
          order_by: [asc: fragment("length(?)", v.title)],
          limit: 1
      )
  end

if is_nil(vn) do
  IO.puts("No VN found for: #{search}")
  System.halt(1)
end

IO.puts("\n  #{vn.title} (#{vn.vndb_id})\n")

# Query both directions via union
forward =
  from s in Similarity,
    join: other in VisualNovel,
    on: other.id == s.similar_vn_id,
    where: s.visual_novel_id == ^vn.id,
    select: %{score: s.score, title: other.title, vndb_id: other.vndb_id}

reverse =
  from s in Similarity,
    join: other in VisualNovel,
    on: other.id == s.visual_novel_id,
    where: s.similar_vn_id == ^vn.id,
    select: %{score: s.score, title: other.title, vndb_id: other.vndb_id}

results =
  from(q in subquery(union_all(forward, ^reverse)),
    order_by: [desc: q.score],
    limit: 20
  )
  |> Repo.all()

if results == [] do
  IO.puts("  No similarities found.")
else
  results
  |> Enum.with_index(1)
  |> Enum.each(fn {%{score: score, title: title, vndb_id: vndb_id}, i} ->
    IO.puts(
      "  #{String.pad_leading("#{i}", 2)}. #{:erlang.float_to_binary(score, decimals: 4)} │ #{vndb_id} │ #{title}"
    )
  end)
end

IO.puts("")
