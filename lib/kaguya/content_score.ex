defmodule Kaguya.ContentScore do
  @moduledoc """
  Computes the per-entity completeness score (0–100) shown in the editor
  sidebar — modeled on TMDB's content score.

  Each check is a boolean validation; the score is `passed / total * 100`,
  rounded. Checks are listed declaratively in `@vn_checks` so adding a new
  one is a single tuple — no migration needed (the breakdown column is
  jsonb; missing keys default to false on read).

  Stored breakdown is jsonb with string keys (e.g. `%{"has_cover" => true}`).
  In-memory breakdowns use the same string-key shape end-to-end so callers
  don't have to care about the persistence boundary.

  After every user edit / create / revert that touches a VN,
  `Kaguya.Revisions` calls `recompute_visual_novel/1` to persist the new
  score. Bulk paths (VNDB dump-sync, the `mix kaguya.backfill_content_scores`
  task) use `recompute_for_vns/1` and `recompute_all/1`.
  """

  import Ecto.Query
  alias Kaguya.Repo
  alias Kaguya.Revisions.Change
  alias Kaguya.Users.User
  alias Kaguya.VisualNovels.{VisualNovel, VNTag}
  alias Kaguya.Producers.VNProducer
  alias Kaguya.Screenshots.Screenshot
  alias Kaguya.Tags.Tag

  # Order is the surfaced order in the UI breakdown.
  @vn_checks [
    %{key: "has_cover", label: "Cover image"},
    %{key: "has_title", label: "Title"},
    %{key: "has_description", label: "Description"},
    %{key: "has_producer", label: "Producer"},
    %{key: "has_two_genre_tags", label: "2+ genre tags"},
    %{key: "has_backdrop", label: "Backdrop"}
  ]

  @description_min_chars 200

  @doc "Public list of VN checks for UI labeling."
  def vn_checks, do: @vn_checks

  @doc """
  Returns the top human contributors for a visual novel, excluding system and
  VNDB-sync revisions.
  """
  def top_contributors_for_visual_novel(vn_id, limit \\ 4)
      when is_binary(vn_id) and is_integer(limit) do
    limit = max(limit, 0)

    from(c in Change,
      join: u in User,
      on: u.id == c.user_id,
      where: c.entity_type == :visual_novel,
      where: c.entity_id == ^vn_id,
      where: c.source == :user,
      group_by: u.id,
      order_by: [desc: count(c.id), asc: u.username],
      limit: ^limit,
      select: %{user: u, edit_count: count(c.id)}
    )
    |> Repo.all()
  end

  @doc """
  Computes the score for a VN without persisting. Returns
  `%{score, passed, total, breakdown}` (breakdown keyed by string), or `nil`
  if the VN doesn't exist.

  Note: this is the single-VN path used by the on-edit hook. For batch
  paths (backfill, post-sync) use `recompute_for_vns/1` — it processes N
  VNs in a single fact-load query and a single bulk UPDATE.
  """
  def compute_visual_novel(vn_id) when is_binary(vn_id) do
    case load_facts_for_vns([vn_id]) do
      [row] -> compute_for_row(row)
      [] -> nil
    end
  end

  def compute_visual_novel(%VisualNovel{id: id}), do: compute_visual_novel(id)

  @doc """
  Recomputes and persists the score for a single VN. Idempotent.

  Safe to call from outside a transaction. Returns `{:ok, :scored}` on
  success, `{:ok, :not_found}` if the VN doesn't exist.
  """
  def recompute_visual_novel(vn_id) when is_binary(vn_id) do
    case recompute_for_vns([vn_id]) do
      %{scored: 1} -> {:ok, :scored}
      %{not_found: 1} -> {:ok, :not_found}
    end
  end

  @doc """
  Recomputes scores for a batch of VN IDs. Two queries total regardless of
  batch size: one fact-load join + one `UPDATE … FROM unnest(...)` bulk
  write. Skips IDs that don't exist (they show up as `not_found`).

  Caller is responsible for chunking — keep batches under a few thousand
  to stay within Postgrex's parameter limits and to keep the array
  payloads from ballooning.

  Returns `%{scored: int, not_found: int}`.
  """
  def recompute_for_vns([]), do: %{scored: 0, not_found: 0}

  def recompute_for_vns(vn_ids) when is_list(vn_ids) do
    rows = load_facts_for_vns(vn_ids)
    computations = Enum.map(rows, &compute_for_row/1)

    persist_batch(computations)

    scored = length(computations)
    %{scored: scored, not_found: length(vn_ids) - scored}
  end

  @doc """
  Recomputes scores for every visible VN. Streams IDs in a short
  read-only transaction (required by `Repo.stream`), then iterates the
  collected IDs *outside* that transaction so per-row writes don't extend
  the cursor's lifetime.

  Options:
    * `:batch_size` (default 500) — application-level chunk size for logging cadence.
    * `:on_batch` (default no-op) — `fn batch_idx, batch_count, totals -> any() end`,
      called after each batch finishes.
  """
  def recompute_all(opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, 500)
    on_batch = Keyword.get(opts, :on_batch, fn _, _, _ -> :ok end)

    {:ok, ids} =
      Repo.transaction(
        fn ->
          from(vn in VisualNovel,
            where: is_nil(vn.hidden_at),
            select: vn.id,
            order_by: vn.id
          )
          |> Repo.stream(max_rows: batch_size)
          |> Enum.to_list()
        end,
        timeout: :infinity
      )

    ids
    |> Stream.chunk_every(batch_size)
    |> Stream.with_index(1)
    |> Enum.reduce(%{scored: 0, not_found: 0}, fn {batch, batch_idx}, acc ->
      result = recompute_for_vns(batch)
      totals = %{scored: acc.scored + result.scored, not_found: acc.not_found + result.not_found}
      on_batch.(batch_idx, length(batch), totals)
      totals
    end)
  end

  # ============================================================================
  # Internals
  # ============================================================================

  # One DB round-trip for any number of VNs. left_join + count over distinct
  # child PKs so VNs with no producers/tags/screenshots still produce a row
  # (counts of 0). vn.id is the primary key, so the non-aggregate columns
  # are functionally dependent and Postgres allows them under GROUP BY vn.id.
  defp load_facts_for_vns([]), do: []

  defp load_facts_for_vns(vn_ids) do
    from(vn in VisualNovel,
      where: vn.id in ^vn_ids,
      left_join: vp in VNProducer,
      on: vp.visual_novel_id == vn.id,
      left_join: vt in VNTag,
      on: vt.visual_novel_id == vn.id,
      left_join: t in Tag,
      on: t.id == vt.tag_id and t.kind == ^:genre,
      left_join: s in Screenshot,
      on: s.visual_novel_id == vn.id,
      group_by: vn.id,
      select: %{
        id: vn.id,
        title: vn.title,
        description: vn.description,
        primary_image_id: vn.primary_image_id,
        featured_screenshot_id: vn.featured_screenshot_id,
        producer_count: fragment("count(distinct ?)", vp.producer_id),
        genre_tag_count: fragment("count(distinct ?)", t.id),
        screenshot_count: fragment("count(distinct ?)", s.id)
      }
    )
    |> Repo.all()
  end

  # Pure: given a fact-row, return the persisted shape `%{id, score, breakdown}`.
  defp compute_for_row(row) do
    breakdown = Map.new(@vn_checks, fn %{key: key} -> {key, evaluate(key, row)} end)
    passed = Enum.count(breakdown, fn {_k, v} -> v end)
    total = length(@vn_checks)
    score = if total == 0, do: 0, else: round(passed / total * 100)

    %{id: row.id, score: score, passed: passed, total: total, breakdown: breakdown}
  end

  # Single bulk UPDATE: one round-trip regardless of batch size. Uses
  # `unnest(uuid[], smallint[], text[])` to zip per-row arrays into a
  # `(id, score, breakdown)` table, joined to `visual_novels` for the write.
  defp persist_batch([]), do: :ok

  defp persist_batch(computations) do
    # Dump each UUID to its 16-byte binary form — Postgrex's `uuid[]` array
    # encoder expects binary, not the canonical string format.
    ids = Enum.map(computations, fn c -> Ecto.UUID.dump!(c.id) end)
    scores = Enum.map(computations, & &1.score)
    breakdowns = Enum.map(computations, fn c -> Jason.encode!(c.breakdown) end)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.query!(
      """
      UPDATE visual_novels AS vn
      SET content_score = data.score,
          content_score_breakdown = data.breakdown::jsonb,
          content_score_updated_at = $4
      FROM unnest($1::uuid[], $2::smallint[], $3::text[])
        AS data(id, score, breakdown)
      WHERE vn.id = data.id
      """,
      [ids, scores, breakdowns, now]
    )

    :ok
  end

  defp evaluate("has_cover", row), do: not is_nil(row.primary_image_id)

  defp evaluate("has_title", row), do: present?(row.title)

  defp evaluate("has_description", row) do
    case row.description do
      nil -> false
      "" -> false
      desc -> desc |> String.trim() |> String.length() >= @description_min_chars
    end
  end

  defp evaluate("has_producer", %{producer_count: n}), do: n >= 1

  defp evaluate("has_two_genre_tags", %{genre_tag_count: n}), do: n >= 2

  # featured_screenshot_id is the editorially picked backdrop; any
  # screenshot also counts so VNs with imported screenshots aren't penalized.
  defp evaluate("has_backdrop", row) do
    not is_nil(row.featured_screenshot_id) or row.screenshot_count >= 1
  end

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(s) when is_binary(s), do: String.trim(s) != ""
end
