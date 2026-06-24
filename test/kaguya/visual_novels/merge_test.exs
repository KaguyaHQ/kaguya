defmodule Kaguya.VisualNovels.MergeTest do
  @moduledoc """
  Tests for `Kaguya.VisualNovels.Merge`.

  Priority order: **user-data preservation rules first** (the load-bearing
  promise of the merge feature), then validation, then association
  migration, then audit + post-merge state.

  Pattern mirrors `test/kaguya/content_score_test.exs`: `async: false`,
  Sandbox checkout per test, inline fixtures with random suffixes for
  unique slugs/usernames.
  """
  use ExUnit.Case, async: false

  import Ecto.Query
  alias Ecto.Adapters.SQL.Sandbox
  alias Kaguya.AuditLog.Entry, as: AuditEntry
  alias Kaguya.Repo
  alias Kaguya.Reviews.{Rating, Review}
  alias Kaguya.Revisions.Change
  alias Kaguya.Shelves.ReadingStatus
  alias Kaguya.Tags.Tag
  alias Kaguya.Users.User
  alias Kaguya.VisualNovels.{Merge, VisualNovel, VNTag}

  setup do
    :ok = Sandbox.checkout(Repo)
    :ok
  end

  # ──────────────────────────────────────────────────────────────────────
  # User-data preservation (the load-bearing rules)
  # ──────────────────────────────────────────────────────────────────────

  describe "user data preservation — ratings (most-recent wins)" do
    test "user with rating on canonical only — preserved" do
      [canonical, source] = insert_two_vns!()
      user = insert_user!()
      insert_rating!(user, canonical, 4.0)

      {:ok, _} = Merge.merge_vns(canonical.id, [source.id], nil, [])

      assert [rating] = Repo.all(from r in Rating, where: r.user_id == ^user.id)
      assert rating.visual_novel_id == canonical.id
      assert rating.rating == 4.0
    end

    test "user with rating on source only — re-pointed to canonical" do
      [canonical, source] = insert_two_vns!()
      user = insert_user!()
      insert_rating!(user, source, 3.5)

      {:ok, _} = Merge.merge_vns(canonical.id, [source.id], nil, [])

      assert [rating] = Repo.all(from r in Rating, where: r.user_id == ^user.id)
      assert rating.visual_novel_id == canonical.id
      assert rating.rating == 3.5
    end

    test "user has rating on both — most-recent updated_at wins" do
      [canonical, source] = insert_two_vns!()
      user = insert_user!()
      old_at = ~U[2024-01-01 00:00:00Z]
      new_at = ~U[2025-06-01 00:00:00Z]
      insert_rating!(user, canonical, 4.0, updated_at: old_at)
      insert_rating!(user, source, 2.5, updated_at: new_at)

      {:ok, _} = Merge.merge_vns(canonical.id, [source.id], nil, [])

      ratings = Repo.all(from r in Rating, where: r.user_id == ^user.id)
      assert length(ratings) == 1
      assert hd(ratings).rating == 2.5
      assert hd(ratings).visual_novel_id == canonical.id
    end

    test "two users — one only on canonical, one only on source — both kept" do
      [canonical, source] = insert_two_vns!()
      u1 = insert_user!()
      u2 = insert_user!()
      insert_rating!(u1, canonical, 4.0)
      insert_rating!(u2, source, 3.0)

      {:ok, _} = Merge.merge_vns(canonical.id, [source.id], nil, [])

      ratings = Repo.all(from r in Rating, order_by: r.user_id)
      assert length(ratings) == 2
      assert Enum.all?(ratings, &(&1.visual_novel_id == canonical.id))
    end

    test "three sources, same user has rating on all — picks the most recent" do
      canonical = insert_vn!()
      [s1, s2, s3] = [insert_vn!(), insert_vn!(), insert_vn!()]
      user = insert_user!()
      insert_rating!(user, s1, 3.0, updated_at: ~U[2024-01-01 00:00:00Z])
      insert_rating!(user, s2, 4.5, updated_at: ~U[2025-12-01 00:00:00Z])
      insert_rating!(user, s3, 2.0, updated_at: ~U[2025-03-01 00:00:00Z])

      {:ok, _} = Merge.merge_vns(canonical.id, [s1.id, s2.id, s3.id], nil, [])

      ratings = Repo.all(from r in Rating, where: r.user_id == ^user.id)
      assert length(ratings) == 1
      assert hd(ratings).rating == 4.5
      assert hd(ratings).visual_novel_id == canonical.id
    end
  end

  describe "user data preservation — reviews (most-recent wins; content longest tiebreak)" do
    test "user with review on canonical only — preserved" do
      [canonical, source] = insert_two_vns!()
      user = insert_user!()
      insert_review!(user, canonical, "Great VN.")

      {:ok, _} = Merge.merge_vns(canonical.id, [source.id], nil, [])

      assert [r] = Repo.all(from r in Review, where: r.user_id == ^user.id)
      assert r.content == "Great VN."
      assert r.visual_novel_id == canonical.id
    end

    test "user has review on both — most-recent wins" do
      [canonical, source] = insert_two_vns!()
      user = insert_user!()
      insert_review!(user, canonical, "Old take.", updated_at: ~U[2024-01-01 00:00:00Z])
      insert_review!(user, source, "Newer thoughts.", updated_at: ~U[2025-06-01 00:00:00Z])

      {:ok, _} = Merge.merge_vns(canonical.id, [source.id], nil, [])

      assert [r] = Repo.all(from r in Review, where: r.user_id == ^user.id)
      assert r.content == "Newer thoughts."
    end

    test "tied updated_at — longer content wins" do
      [canonical, source] = insert_two_vns!()
      user = insert_user!()
      same_time = ~U[2025-01-01 00:00:00Z]
      insert_review!(user, canonical, "Short.", updated_at: same_time)

      insert_review!(user, source, "This is a substantially longer review.",
        updated_at: same_time
      )

      {:ok, _} = Merge.merge_vns(canonical.id, [source.id], nil, [])

      assert [r] = Repo.all(from r in Review, where: r.user_id == ^user.id)
      assert r.content == "This is a substantially longer review."
    end
  end

  describe "user data preservation — reading_statuses (most-progressed wins)" do
    test "user has 'currently_reading' on canonical, 'read' on source — read wins" do
      [canonical, source] = insert_two_vns!()
      user = insert_user!()
      insert_reading_status!(user, canonical, "currently_reading")
      insert_reading_status!(user, source, "read")

      {:ok, _} = Merge.merge_vns(canonical.id, [source.id], nil, [])

      assert [s] = Repo.all(from s in ReadingStatus, where: s.user_id == ^user.id)
      assert s.status == :read
      assert s.visual_novel_id == canonical.id
    end

    test "user has 'on_hold' on source, 'want_to_read' on canonical — on_hold wins" do
      [canonical, source] = insert_two_vns!()
      user = insert_user!()
      insert_reading_status!(user, canonical, "want_to_read")
      insert_reading_status!(user, source, "on_hold")

      {:ok, _} = Merge.merge_vns(canonical.id, [source.id], nil, [])

      assert [s] = Repo.all(from s in ReadingStatus, where: s.user_id == ^user.id)
      assert s.status == :on_hold
    end

    test "tied status — most recent updated_at wins" do
      [canonical, source] = insert_two_vns!()
      user = insert_user!()
      old_at = ~U[2024-01-01 00:00:00Z]
      new_at = ~U[2025-06-01 00:00:00Z]
      insert_reading_status!(user, canonical, "read", updated_at: old_at)
      insert_reading_status!(user, source, "read", updated_at: new_at)

      {:ok, _} = Merge.merge_vns(canonical.id, [source.id], nil, [])

      assert [s] = Repo.all(from s in ReadingStatus, where: s.user_id == ^user.id)
      assert s.updated_at |> DateTime.to_iso8601() == "2025-06-01T00:00:00Z"
    end
  end

  # ──────────────────────────────────────────────────────────────────────
  # Tag aggregation (vote_count summed, no double-count via per-user dedup)
  # ──────────────────────────────────────────────────────────────────────

  describe "vn_tags aggregation" do
    test "same tag on both — vote counts sum" do
      [canonical, source] = insert_two_vns!()
      tag = insert_tag!()
      insert_vn_tag!(canonical, tag, vndb_vote_count: 5)
      insert_vn_tag!(source, tag, vndb_vote_count: 7)

      {:ok, _} = Merge.merge_vns(canonical.id, [source.id], nil, [])

      assert [vt] = Repo.all(from vt in VNTag, where: vt.visual_novel_id == ^canonical.id)
      assert vt.vndb_vote_count == 12
    end

    test "tag only on source — re-pointed to canonical" do
      [canonical, source] = insert_two_vns!()
      tag = insert_tag!()
      insert_vn_tag!(source, tag, vndb_vote_count: 4)

      {:ok, _} = Merge.merge_vns(canonical.id, [source.id], nil, [])

      assert [vt] = Repo.all(from vt in VNTag, where: vt.visual_novel_id == ^canonical.id)
      assert vt.tag_id == tag.id
      assert vt.vndb_vote_count == 4
    end

    test "spoiler_level — max wins" do
      [canonical, source] = insert_two_vns!()
      tag = insert_tag!()
      insert_vn_tag!(canonical, tag, spoiler_level: 0)
      insert_vn_tag!(source, tag, spoiler_level: 2)

      {:ok, _} = Merge.merge_vns(canonical.id, [source.id], nil, [])

      assert [vt] = Repo.all(from vt in VNTag, where: vt.visual_novel_id == ^canonical.id)
      # Ecto.Enum maps smallint 2 → :major
      assert vt.spoiler_level == :major
    end

    test "same tag on multiple sources, none on canonical — votes sum into one canonical row" do
      canonical = insert_vn!()
      [s1, s2] = [insert_vn!(), insert_vn!()]
      tag = insert_tag!()
      insert_vn_tag!(s1, tag, vndb_vote_count: 6)
      insert_vn_tag!(s2, tag, vndb_vote_count: 9)

      {:ok, _} = Merge.merge_vns(canonical.id, [s1.id, s2.id], nil, [])

      assert [vt] = Repo.all(from vt in VNTag, where: vt.visual_novel_id == ^canonical.id)
      assert vt.tag_id == tag.id
      assert vt.vndb_vote_count == 15
    end

    test "vote-weighted vndb_avg_score across canonical + multiple sources" do
      canonical = insert_vn!()
      [s1, s2] = [insert_vn!(), insert_vn!()]
      tag = insert_tag!()
      insert_vn_tag!(canonical, tag, vndb_vote_count: 10, vndb_avg_score: 2.0)
      insert_vn_tag!(s1, tag, vndb_vote_count: 5, vndb_avg_score: 3.0)
      insert_vn_tag!(s2, tag, vndb_vote_count: 5, vndb_avg_score: 1.0)

      {:ok, _} = Merge.merge_vns(canonical.id, [s1.id, s2.id], nil, [])

      assert [vt] = Repo.all(from vt in VNTag, where: vt.visual_novel_id == ^canonical.id)
      assert vt.vndb_vote_count == 20
      # Weighted: (2.0*10 + 3.0*5 + 1.0*5) / 20 = 40/20 = 2.0
      assert_in_delta vt.vndb_avg_score, 2.0, 0.001
    end

    test "is_overruled OR across sources" do
      [canonical, source] = insert_two_vns!()
      tag = insert_tag!()
      insert_vn_tag!(canonical, tag, is_overruled: false)
      insert_vn_tag!(source, tag, is_overruled: true)

      {:ok, _} = Merge.merge_vns(canonical.id, [source.id], nil, [])

      assert [vt] = Repo.all(from vt in VNTag, where: vt.visual_novel_id == ^canonical.id)
      assert vt.is_overruled == true
    end
  end

  # ──────────────────────────────────────────────────────────────────────
  # Polymorphic / array ref re-point
  # ──────────────────────────────────────────────────────────────────────

  describe "polymorphic ref migration" do
    test "users.favorite_visual_novels — source replaced with canonical, dedup if both present" do
      [canonical, source] = insert_two_vns!()
      other = insert_vn!()

      u_only_source = insert_user!()
      u_both = insert_user!()
      u_neither = insert_user!()

      set_favorites!(u_only_source, [source.id, other.id])
      set_favorites!(u_both, [canonical.id, source.id, other.id])
      set_favorites!(u_neither, [other.id])

      {:ok, _} = Merge.merge_vns(canonical.id, [source.id], nil, [])

      assert favorites(u_only_source) |> Enum.sort() ==
               Enum.sort([canonical.id, other.id])

      # u_both had both — canonical survives once, no duplicate
      assert favorites(u_both) |> Enum.sort() ==
               Enum.sort([canonical.id, other.id])

      assert favorites(u_neither) == [other.id]
    end

    test "audit_log.target_id — re-pointed for target_type 'visual_novel'" do
      [canonical, source] = insert_two_vns!()
      actor = insert_user!()

      Repo.insert_all("audit_log", [
        %{
          id: Ecto.UUID.dump!(Ecto.UUID.generate()),
          user_id: Ecto.UUID.dump!(actor.id),
          action: "edit_vn",
          target_type: "visual_novel",
          target_id: Ecto.UUID.dump!(source.id),
          details: nil,
          inserted_at: DateTime.utc_now() |> DateTime.truncate(:second)
        }
      ])

      {:ok, _} = Merge.merge_vns(canonical.id, [source.id], nil, [])

      [entry] =
        Repo.all(
          from a in AuditEntry,
            where: a.action == "edit_vn",
            select: %{target_id: a.target_id, target_type: a.target_type}
        )

      assert entry.target_id == canonical.id
      assert entry.target_type == "visual_novel"
    end

    test "notifications.entity_id — re-pointed for entity_type 'visual_novel'" do
      [canonical, source] = insert_two_vns!()
      user = insert_user!()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Repo.insert_all("notifications", [
        %{
          id: Ecto.UUID.dump!(Ecto.UUID.generate()),
          user_id: Ecto.UUID.dump!(user.id),
          action: "vn_locked",
          entity_type: "visual_novel",
          entity_id: Ecto.UUID.dump!(source.id),
          read: false,
          metadata: %{},
          inserted_at: now,
          updated_at: now
        }
      ])

      {:ok, _} = Merge.merge_vns(canonical.id, [source.id], nil, [])

      [%{entity_id: eid}] =
        Repo.all(
          from n in "notifications",
            where: n.entity_type == "visual_novel",
            select: %{entity_id: type(n.entity_id, Ecto.UUID)}
        )

      assert eid == canonical.id
    end
  end

  # ──────────────────────────────────────────────────────────────────────
  # Self-relation tables (vn_relations, vn_similarities)
  # ──────────────────────────────────────────────────────────────────────

  describe "vn_relations migration" do
    test "(canonical,X) + (source,X) — composite unique resolved by priority" do
      [canonical, source, x] = [insert_vn!(), insert_vn!(), insert_vn!()]
      insert_vn_relation!(canonical, x, "fandisc")
      insert_vn_relation!(source, x, "sequel")

      {:ok, _} = Merge.merge_vns(canonical.id, [source.id], nil, [])

      relations =
        Repo.all(
          from r in "vn_relations",
            where: r.visual_novel_id == type(^canonical.id, Ecto.UUID),
            select: %{related_vn_id: type(r.related_vn_id, Ecto.UUID), type: r.relation_type}
        )

      assert length(relations) == 1
      [%{type: type, related_vn_id: rid}] = relations
      assert rid == x.id
      assert type == "sequel"
    end

    test "two sources both relate to X — survives without composite-PK violation" do
      [canonical, s1, s2, x] = [insert_vn!(), insert_vn!(), insert_vn!(), insert_vn!()]
      insert_vn_relation!(s1, x, "fandisc")
      insert_vn_relation!(s2, x, "sequel")

      {:ok, _} = Merge.merge_vns(canonical.id, [s1.id, s2.id], nil, [])

      relations =
        Repo.all(
          from r in "vn_relations",
            where: r.visual_novel_id == type(^canonical.id, Ecto.UUID),
            select: %{related_vn_id: type(r.related_vn_id, Ecto.UUID), type: r.relation_type}
        )

      assert length(relations) == 1
      assert hd(relations).type == "sequel"
    end

    test "relation between canonical and source dissolves" do
      [canonical, source] = insert_two_vns!()
      insert_vn_relation!(canonical, source, "sequel")

      {:ok, _} = Merge.merge_vns(canonical.id, [source.id], nil, [])

      assert Repo.aggregate("vn_relations", :count) == 0
    end

    test "vn_similarities: source's similarity to outside VN survives the merge regardless of UUID order" do
      # vn_similarities has a CHECK `visual_novel_id < similar_vn_id`.
      # The merge must always end up with the canonical pair in the right
      # column, otherwise the CHECK aborts the whole transaction.
      [canonical, source, outside] = [insert_vn!(), insert_vn!(), insert_vn!()]

      # Force the source-outside row's stored shape via LEAST/GREATEST,
      # since we don't know the UUID ordering ahead of time.
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      [lo, hi] = Enum.sort([source.id, outside.id])

      Repo.insert_all("vn_similarities", [
        %{
          visual_novel_id: Ecto.UUID.dump!(lo),
          similar_vn_id: Ecto.UUID.dump!(hi),
          upvotes_count: 3,
          downvotes_count: 1,
          inserted_at: now,
          updated_at: now
        }
      ])

      {:ok, _} = Merge.merge_vns(canonical.id, [source.id], nil, [])

      [%{lo: result_lo, hi: result_hi, up: up, down: down}] =
        Repo.all(
          from s in "vn_similarities",
            where:
              s.visual_novel_id == type(^canonical.id, Ecto.UUID) or
                s.similar_vn_id == type(^canonical.id, Ecto.UUID),
            select: %{
              lo: type(s.visual_novel_id, Ecto.UUID),
              hi: type(s.similar_vn_id, Ecto.UUID),
              up: s.upvotes_count,
              down: s.downvotes_count
            }
        )

      [expected_lo, expected_hi] = Enum.sort([canonical.id, outside.id])
      assert result_lo == expected_lo
      assert result_hi == expected_hi
      assert up == 3
      assert down == 1
    end

    test "vn_similarities: TWO sources with similarities to the same outside VN fold into one canonical row" do
      # Pre-INSERT GROUP BY collapses (s1, X) and (s2, X) to the same
      # canonical-pair so ON CONFLICT doesn't see two new rows targeting
      # the same row (would otherwise raise cardinality_violation).
      canonical = insert_vn!()
      [s1, s2, outside] = [insert_vn!(), insert_vn!(), insert_vn!()]
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      [s1_lo, s1_hi] = Enum.sort([s1.id, outside.id])
      [s2_lo, s2_hi] = Enum.sort([s2.id, outside.id])

      Repo.insert_all("vn_similarities", [
        %{
          visual_novel_id: Ecto.UUID.dump!(s1_lo),
          similar_vn_id: Ecto.UUID.dump!(s1_hi),
          upvotes_count: 4,
          downvotes_count: 0,
          inserted_at: now,
          updated_at: now
        },
        %{
          visual_novel_id: Ecto.UUID.dump!(s2_lo),
          similar_vn_id: Ecto.UUID.dump!(s2_hi),
          upvotes_count: 6,
          downvotes_count: 1,
          inserted_at: now,
          updated_at: now
        }
      ])

      {:ok, _} = Merge.merge_vns(canonical.id, [s1.id, s2.id], nil, [])

      [%{up: up, down: down}] =
        Repo.all(
          from s in "vn_similarities",
            where:
              s.visual_novel_id == type(^canonical.id, Ecto.UUID) or
                s.similar_vn_id == type(^canonical.id, Ecto.UUID),
            select: %{up: s.upvotes_count, down: s.downvotes_count}
        )

      assert up == 10
      assert down == 1
    end

    test "vn_similarities: canonical's and source's similarities to the same outside VN merge into one row, vote counts sum" do
      [canonical, source, outside] = [insert_vn!(), insert_vn!(), insert_vn!()]
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      [c_lo, c_hi] = Enum.sort([canonical.id, outside.id])
      [s_lo, s_hi] = Enum.sort([source.id, outside.id])

      Repo.insert_all("vn_similarities", [
        %{
          visual_novel_id: Ecto.UUID.dump!(c_lo),
          similar_vn_id: Ecto.UUID.dump!(c_hi),
          upvotes_count: 5,
          downvotes_count: 0,
          inserted_at: now,
          updated_at: now
        },
        %{
          visual_novel_id: Ecto.UUID.dump!(s_lo),
          similar_vn_id: Ecto.UUID.dump!(s_hi),
          upvotes_count: 2,
          downvotes_count: 3,
          inserted_at: now,
          updated_at: now
        }
      ])

      {:ok, _} = Merge.merge_vns(canonical.id, [source.id], nil, [])

      rows =
        Repo.all(
          from s in "vn_similarities",
            where:
              s.visual_novel_id == type(^canonical.id, Ecto.UUID) or
                s.similar_vn_id == type(^canonical.id, Ecto.UUID),
            select: %{up: s.upvotes_count, down: s.downvotes_count}
        )

      assert length(rows) == 1
      assert hd(rows).up == 7
      assert hd(rows).down == 3
    end

    test "related_col side: (X, source) re-points to (X, canonical) without violating uniques" do
      [canonical, source, x] = [insert_vn!(), insert_vn!(), insert_vn!()]
      insert_vn_relation!(x, canonical, "sequel")
      insert_vn_relation!(x, source, "fandisc")

      {:ok, _} = Merge.merge_vns(canonical.id, [source.id], nil, [])

      relations =
        Repo.all(
          from r in "vn_relations",
            where: r.related_vn_id == type(^canonical.id, Ecto.UUID),
            select: %{visual_novel_id: type(r.visual_novel_id, Ecto.UUID), type: r.relation_type}
        )

      assert length(relations) == 1
      assert hd(relations).visual_novel_id == x.id
      assert hd(relations).type == "sequel"
    end
  end

  # ──────────────────────────────────────────────────────────────────────
  # Secondary-unique re-point (vn_titles, vn_images, vn_releases)
  # ──────────────────────────────────────────────────────────────────────

  describe "secondary-unique tables — duplicates resolved without crashing" do
    test "vn_titles — both VNs have a 'ja' title; canonical's row wins" do
      [canonical, source] = insert_two_vns!()
      insert_vn_title!(canonical, "ja", "Canonical JA Title")
      insert_vn_title!(source, "ja", "Source JA Title")
      insert_vn_title!(source, "en", "Source EN Title")

      {:ok, _} = Merge.merge_vns(canonical.id, [source.id], nil, [])

      titles =
        Repo.all(
          from t in "vn_titles",
            where: t.visual_novel_id == type(^canonical.id, Ecto.UUID),
            select: %{lang: t.lang, title: t.title}
        )

      assert length(titles) == 2
      ja = Enum.find(titles, &(&1.lang == "ja"))
      en = Enum.find(titles, &(&1.lang == "en"))
      assert ja.title == "Canonical JA Title"
      assert en.title == "Source EN Title"
    end

    test "vn_images — same VNDB cover id on canonical + source; canonical row wins" do
      [canonical, source] = insert_two_vns!()
      insert_vn_image!(canonical, "ccover1", width: 800)
      insert_vn_image!(source, "ccover1", width: 999)
      insert_vn_image!(source, "ccover2", width: 600)

      {:ok, _} = Merge.merge_vns(canonical.id, [source.id], nil, [])

      images =
        Repo.all(
          from i in "vn_images",
            where: i.visual_novel_id == type(^canonical.id, Ecto.UUID),
            select: %{vndb_cv_id: i.vndb_cv_id, width: i.width}
        )

      assert length(images) == 2
      shared = Enum.find(images, &(&1.vndb_cv_id == "ccover1"))
      assert shared.width == 800
    end

    test "vn_releases — same VNDB release id on canonical + source; canonical row wins" do
      [canonical, source] = insert_two_vns!()
      insert_vn_release!(canonical, "r1", "Canonical Release Title")
      insert_vn_release!(source, "r1", "Source Release Title")
      insert_vn_release!(source, "r2", "Source-only Release")

      {:ok, _} = Merge.merge_vns(canonical.id, [source.id], nil, [])

      releases =
        Repo.all(
          from r in "vn_releases",
            where: r.visual_novel_id == type(^canonical.id, Ecto.UUID),
            select: %{vndb_id: r.vndb_id, title: r.title}
        )

      assert length(releases) == 2
      shared = Enum.find(releases, &(&1.vndb_id == "r1"))
      assert shared.title == "Canonical Release Title"
    end
  end

  # ──────────────────────────────────────────────────────────────────────
  # Aggregate recompute
  # ──────────────────────────────────────────────────────────────────────

  describe "post-merge canonical row" do
    test "ratings_count and ratings_dist rebuilt from surviving rows" do
      [canonical, source] = insert_two_vns!()
      u1 = insert_user!()
      u2 = insert_user!()
      u3 = insert_user!()
      insert_rating!(u1, canonical, 4.0)
      insert_rating!(u2, source, 3.0)
      # u3 had a rating on both — only most-recent should survive
      insert_rating!(u3, canonical, 5.0, updated_at: ~U[2024-01-01 00:00:00Z])
      insert_rating!(u3, source, 2.0, updated_at: ~U[2025-01-01 00:00:00Z])

      {:ok, _} = Merge.merge_vns(canonical.id, [source.id], nil, [])

      vn = Repo.get!(VisualNovel, canonical.id)
      assert vn.ratings_count == 3
      # Three ratings: 4.0, 3.0, 2.0 — buckets 8, 6, 4 (1-indexed by rating*2)
      # 4.0 → bucket index 7
      assert Enum.at(vn.ratings_dist, 7) == 1
      # 3.0 → bucket index 5
      assert Enum.at(vn.ratings_dist, 5) == 1
      # 2.0 → bucket index 3
      assert Enum.at(vn.ratings_dist, 3) == 1
    end

    test "title and description from canonical by default" do
      canonical = insert_vn!(title: "Summer's Gone")

      source =
        insert_vn!(title: "Summer's Gone: Season 1", description: String.duplicate("X", 1000))

      {:ok, _} = Merge.merge_vns(canonical.id, [source.id], nil, [])

      vn = Repo.get!(VisualNovel, canonical.id)
      assert vn.title == "Summer's Gone"
      # description: longer wins (1000 X's vs canonical's nil)
      assert String.length(vn.description) == 1000
    end

    test "aliases gets union of source titles + canonical's aliases" do
      canonical = insert_vn!(title: "Summer's Gone", aliases: ["SG"])
      source = insert_vn!(title: "Summer's Gone: Season 1")

      {:ok, _} = Merge.merge_vns(canonical.id, [source.id], nil, [])

      vn = Repo.get!(VisualNovel, canonical.id)
      assert "SG" in vn.aliases
      assert "Summer's Gone: Season 1" in vn.aliases
      refute "Summer's Gone" in vn.aliases
    end

    test "development_status — most-active priority wins" do
      canonical = insert_vn!(development_status: "finished")
      source = insert_vn!(development_status: "in_development")

      {:ok, _} = Merge.merge_vns(canonical.id, [source.id], nil, [])

      vn = Repo.get!(VisualNovel, canonical.id)
      assert vn.development_status == "in_development"
    end

    test "has_ero — any-true OR" do
      canonical = insert_vn!(has_ero: false)
      source = insert_vn!(has_ero: true)

      {:ok, _} = Merge.merge_vns(canonical.id, [source.id], nil, [])

      assert Repo.get!(VisualNovel, canonical.id).has_ero == true
    end

    test "release_date — earliest wins" do
      canonical = insert_vn!(release_date: ~D[2024-06-01])
      source = insert_vn!(release_date: ~D[2023-01-01])

      {:ok, _} = Merge.merge_vns(canonical.id, [source.id], nil, [])

      assert Repo.get!(VisualNovel, canonical.id).release_date == ~D[2023-01-01]
    end

    test "slug override — applied to canonical row (not silently dropped)" do
      canonical =
        insert_vn!(
          title: "Summer's Gone: Season 1",
          slug: "summers-gone-s1-#{System.unique_integer([:positive])}"
        )

      source = insert_vn!(title: "Summer's Gone: Season 2")
      target_slug = "summers-gone-#{System.unique_integer([:positive])}"

      {:ok, _} =
        Merge.merge_vns(canonical.id, [source.id], nil, attrs: %{slug: target_slug})

      assert Repo.get!(VisualNovel, canonical.id).slug == target_slug
    end

    test "length_minutes — summed across all merged rows" do
      canonical = insert_vn!(length_minutes: 600)
      s1 = insert_vn!(length_minutes: 300)
      s2 = insert_vn!(length_minutes: 200)

      {:ok, _} = Merge.merge_vns(canonical.id, [s1.id, s2.id], nil, [])

      assert Repo.get!(VisualNovel, canonical.id).length_minutes == 1100
    end

    test "is_locked — any-true OR (a locked source flips an unlocked canonical)" do
      canonical = insert_vn!(is_locked: false)
      source = insert_vn!(is_locked: true)

      {:ok, _} = Merge.merge_vns(canonical.id, [source.id], nil, [])

      assert Repo.get!(VisualNovel, canonical.id).is_locked == true
    end

    test "hidden_at — earliest non-nil wins" do
      hidden = ~U[2026-01-15 00:00:00Z]
      canonical = insert_vn!()
      source = insert_vn!(hidden_at: hidden)

      {:ok, _} = Merge.merge_vns(canonical.id, [source.id], nil, [])

      assert DateTime.compare(Repo.get!(VisualNovel, canonical.id).hidden_at, hidden) == :eq
    end

    test "is_cover_pinned — any-true OR" do
      canonical = insert_vn!(is_cover_pinned: false)
      source = insert_vn!(is_cover_pinned: true)

      {:ok, _} = Merge.merge_vns(canonical.id, [source.id], nil, [])

      assert Repo.get!(VisualNovel, canonical.id).is_cover_pinned == true
    end
  end

  # ──────────────────────────────────────────────────────────────────────
  # vn_merges registry + audit
  # ──────────────────────────────────────────────────────────────────────

  describe "audit trail and registry" do
    test "vn_merges row created with source's slug, title, vndb_id" do
      canonical = insert_vn!(title: "Summer's Gone")
      source = insert_vn!(title: "Summer's Gone: Season 1", vndb_id: "v27557")

      {:ok, _} = Merge.merge_vns(canonical.id, [source.id], nil, [])

      [merge] =
        Repo.all(
          from m in "vn_merges",
            select: %{
              merged_id: type(m.merged_id, Ecto.UUID),
              canonical_id: type(m.canonical_id, Ecto.UUID),
              merged_slug: m.merged_slug,
              merged_title: m.merged_title,
              merged_vndb_id: m.merged_vndb_id
            }
        )

      assert merge.merged_id == source.id
      assert merge.canonical_id == canonical.id
      assert merge.merged_slug == source.slug
      assert merge.merged_title == "Summer's Gone: Season 1"
      assert merge.merged_vndb_id == "v27557"
    end

    test "audit_log row written when actor_user_id given" do
      [canonical, source] = insert_two_vns!()
      actor = insert_user!()

      {:ok, _} = Merge.merge_vns(canonical.id, [source.id], actor.id, [])

      assert [entry] = Repo.all(AuditEntry)
      assert entry.user_id == actor.id
      assert entry.action == "merge_vn"
      assert entry.target_type == "visual_novel"
      assert entry.target_id == canonical.id
    end

    test "no audit_log row when actor_user_id is nil" do
      [canonical, source] = insert_two_vns!()

      {:ok, _} = Merge.merge_vns(canonical.id, [source.id], nil, [])

      assert Repo.aggregate(AuditEntry, :count) == 0
    end

    test "Revisions :edit row created on canonical with merged_from changed_field" do
      [canonical, source] = insert_two_vns!()

      {:ok, _} = Merge.merge_vns(canonical.id, [source.id], nil, [])

      assert [change] =
               Repo.all(
                 from c in Change, where: c.entity_id == ^canonical.id and c.action == :edit
               )

      assert "merged_from" in change.changed_fields
    end

    test "source visual_novels row deleted" do
      [canonical, source] = insert_two_vns!()

      {:ok, _} = Merge.merge_vns(canonical.id, [source.id], nil, [])

      assert Repo.get(VisualNovel, source.id) == nil
      assert Repo.get(VisualNovel, canonical.id) != nil
    end
  end

  # ──────────────────────────────────────────────────────────────────────
  # Validation
  # ──────────────────────────────────────────────────────────────────────

  describe "validation" do
    test "self-merge rejected" do
      vn = insert_vn!()
      assert {:error, :self_merge} = Merge.merge_vns(vn.id, [vn.id], nil, [])
    end

    test "empty source list rejected" do
      vn = insert_vn!()
      assert {:error, :no_sources} = Merge.merge_vns(vn.id, [], nil, [])
    end

    test "duplicate source ids rejected" do
      [canonical, source] = insert_two_vns!()

      assert {:error, :duplicate_source_ids} =
               Merge.merge_vns(canonical.id, [source.id, source.id], nil, [])
    end

    test "missing canonical id rejected" do
      source = insert_vn!()
      missing = Ecto.UUID.generate()

      assert {:error, {:vn_not_found, ^missing}} =
               Merge.merge_vns(missing, [source.id], nil, [])
    end

    test "missing source id rejected" do
      canonical = insert_vn!()
      missing = Ecto.UUID.generate()

      assert {:error, {:sources_not_found, [^missing]}} =
               Merge.merge_vns(canonical.id, [missing], nil, [])
    end
  end

  # ──────────────────────────────────────────────────────────────────────
  # Slug redirect via vn_merges (URL/share-link survival)
  # ──────────────────────────────────────────────────────────────────────

  describe "slug redirect after merge" do
    test "old slug resolves to canonical VN" do
      canonical = insert_vn!(title: "Summer's Gone")
      source = insert_vn!(title: "Summer's Gone: Season 1")
      source_slug = source.slug

      {:ok, _} = Merge.merge_vns(canonical.id, [source.id], nil, [])

      # Source is gone — direct slug match returns nil...
      refute Repo.get_by(VisualNovel, slug: source_slug)

      # ...but the context resolver falls back to vn_merges and returns
      # the canonical, so cached client URLs / external links survive.
      result = Kaguya.VisualNovels.get_visual_novel_by_slug(source_slug)
      assert result != nil
      assert result.id == canonical.id
    end

    test "canonical's own slug still resolves" do
      [canonical, source] = insert_two_vns!()

      {:ok, _} = Merge.merge_vns(canonical.id, [source.id], nil, [])

      direct = Kaguya.VisualNovels.get_visual_novel_by_slug(canonical.slug)
      assert direct.id == canonical.id
    end

    test "unknown slug still returns nil" do
      assert Kaguya.VisualNovels.get_visual_novel_by_slug("not-a-real-slug-#{suffix()}") == nil
    end

    test "resolve_vn_id_by_slug/1 — canonical slug returns canonical id" do
      [canonical, source] = insert_two_vns!()

      {:ok, _} = Merge.merge_vns(canonical.id, [source.id], nil, [])

      assert Kaguya.VisualNovels.resolve_vn_id_by_slug(canonical.slug) == canonical.id
    end

    test "resolve_vn_id_by_slug/1 — merged source slug returns canonical id" do
      [canonical, source] = insert_two_vns!()
      source_slug = source.slug

      {:ok, _} = Merge.merge_vns(canonical.id, [source.id], nil, [])

      assert Kaguya.VisualNovels.resolve_vn_id_by_slug(source_slug) == canonical.id
    end

    test "canonical's old slug also redirects when --slug overrides it" do
      canonical = insert_vn!()
      source = insert_vn!()
      old_canonical_slug = canonical.slug
      new_slug = "renamed-canonical-#{System.unique_integer([:positive])}"

      {:ok, _} =
        Merge.merge_vns(canonical.id, [source.id], nil, attrs: %{slug: new_slug})

      # Direct lookup of the new slug works.
      assert Repo.get!(VisualNovel, canonical.id).slug == new_slug

      # The OLD canonical slug also resolves back to the (now-renamed)
      # canonical via vn_merges fallback — preserving links to URLs
      # users / external sites already had.
      assert Kaguya.VisualNovels.resolve_vn_id_by_slug(old_canonical_slug) == canonical.id
      assert Kaguya.VisualNovels.get_visual_novel_by_slug(old_canonical_slug).id == canonical.id
    end

    test "canonical rename: old slug resolves; canonical's vndb_id stays out of sync skip-list" do
      canonical = insert_vn!()
      source = insert_vn!()
      new_slug = "rename-#{System.unique_integer([:positive])}"

      {:ok, _} =
        Merge.merge_vns(canonical.id, [source.id], nil, attrs: %{slug: new_slug})

      # Canonical's old slug now lives in slug_redirects (not vn_merges).
      assert Kaguya.SlugRedirects.resolve(:vn, canonical.slug) == canonical.id

      # vn_merges only carries source rows. Canonical's live vndb_id must
      # not land in the skip-list, or VNDB sync would stop refreshing it.
      skip_list_ids =
        Repo.all(from m in "vn_merges", select: m.merged_vndb_id)
        |> Enum.reject(&is_nil/1)

      refute canonical.vndb_id in skip_list_ids
    end

    test "resolve_vn_id_by_slug/1 — unknown slug returns nil" do
      assert Kaguya.VisualNovels.resolve_vn_id_by_slug("never-seen-#{suffix()}") == nil
    end

    test "resolve_vn_ids_by_slugs/1 — mixes direct and merged slugs" do
      [canonical, source] = insert_two_vns!()
      direct = insert_vn!()
      source_slug = source.slug
      missing = "no-such-slug-#{suffix()}"

      {:ok, _} = Merge.merge_vns(canonical.id, [source.id], nil, [])

      result =
        Kaguya.VisualNovels.resolve_vn_ids_by_slugs([
          canonical.slug,
          source_slug,
          direct.slug,
          missing
        ])

      assert result[canonical.slug] == canonical.id
      assert result[source_slug] == canonical.id
      assert result[direct.slug] == direct.id
      refute Map.has_key?(result, missing)
    end
  end

  # ──────────────────────────────────────────────────────────────────────
  # Dry run
  # ──────────────────────────────────────────────────────────────────────

  describe "dry-run" do
    test "returns resolved attrs without mutating" do
      canonical = insert_vn!(title: "Summer's Gone", has_ero: false)
      source = insert_vn!(title: "Summer's Gone: Season 1", has_ero: true, vndb_id: "v27557")

      {:ok, summary} = Merge.merge_vns(canonical.id, [source.id], nil, dry_run: true)

      assert summary.dry_run == true
      assert summary.canonical_id == canonical.id
      assert summary.resolved_attrs.has_ero == true

      # No mutation occurred.
      assert Repo.get(VisualNovel, source.id) != nil
      assert Repo.aggregate(from(m in "vn_merges"), :count) == 0
    end
  end

  # ──────────────────────────────────────────────────────────────────────
  # Fixtures
  # ──────────────────────────────────────────────────────────────────────

  defp suffix, do: :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)

  defp insert_vn!(attrs \\ %{}) do
    attrs = ensure_map(attrs)
    s = suffix()
    base = %{title: "Test VN #{s}", original_language: "en"}

    {:ok, vn} =
      %VisualNovel{}
      |> VisualNovel.changeset(Map.merge(base, attrs))
      |> Repo.insert()

    # Fields not in the changeset cast list (has_ero / development_status / etc.)
    # — apply via Ecto.Changeset.change/put_change.
    extra =
      Map.take(attrs, [
        :has_ero,
        :development_status,
        :release_date,
        :aliases,
        :slug,
        :length_minutes,
        :hidden_at,
        :is_locked,
        :is_cover_pinned,
        :featured_screenshot_id
      ])

    if extra == %{} do
      vn
    else
      vn |> Ecto.Changeset.change(extra) |> Repo.update!()
    end
  end

  defp insert_two_vns!, do: [insert_vn!(), insert_vn!()]

  defp insert_user!(attrs \\ %{}) do
    attrs = ensure_map(attrs)
    s = suffix()

    base = %{
      id: Ecto.UUID.generate(),
      username: "user_#{s}",
      display_name: "User #{s}",
      email: "user_#{s}@test.local"
    }

    %User{}
    |> Ecto.Changeset.cast(Map.merge(base, attrs), [:id, :username, :display_name, :email, :role])
    |> Repo.insert!()
  end

  defp ensure_map(attrs) when is_list(attrs), do: Enum.into(attrs, %{})
  defp ensure_map(attrs) when is_map(attrs), do: attrs

  defp insert_rating!(user, vn, rating, opts \\ []) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    updated = Keyword.get(opts, :updated_at, now)

    %{
      user_id: Ecto.UUID.dump!(user.id),
      visual_novel_id: Ecto.UUID.dump!(vn.id),
      rating: rating,
      inserted_at: updated,
      updated_at: updated
    }
    |> then(
      &Repo.insert_all("ratings", [Map.put(&1, :id, Ecto.UUID.dump!(Ecto.UUID.generate()))])
    )
  end

  defp insert_review!(user, vn, content, opts \\ []) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    updated = Keyword.get(opts, :updated_at, now)

    Repo.insert_all("reviews", [
      %{
        id: Ecto.UUID.dump!(Ecto.UUID.generate()),
        user_id: Ecto.UUID.dump!(user.id),
        visual_novel_id: Ecto.UUID.dump!(vn.id),
        content: content,
        likes_count: 0,
        trending_score: 0.0,
        comments_count: 0,
        is_edited: false,
        is_spoiler: false,
        is_locked: false,
        inserted_at: updated,
        updated_at: updated
      }
    ])
  end

  defp insert_reading_status!(user, vn, status, opts \\ []) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    updated = Keyword.get(opts, :updated_at, now)

    Repo.insert_all("reading_statuses", [
      %{
        id: Ecto.UUID.dump!(Ecto.UUID.generate()),
        user_id: Ecto.UUID.dump!(user.id),
        visual_novel_id: Ecto.UUID.dump!(vn.id),
        status: status,
        library_added_at: updated,
        inserted_at: updated,
        updated_at: updated
      }
    ])
  end

  defp insert_tag!(attrs \\ %{}) do
    s = suffix()
    base = %{name: "Test Tag #{s}", slug: "test-tag-#{s}", source: "manual"}

    %Tag{}
    |> Tag.changeset(Map.merge(base, attrs))
    |> Repo.insert!()
  end

  defp insert_vn_tag!(vn, tag, opts) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    row = %{
      visual_novel_id: Ecto.UUID.dump!(vn.id),
      tag_id: Ecto.UUID.dump!(tag.id),
      vndb_vote_count: Keyword.get(opts, :vndb_vote_count, 0),
      relevance_score: Keyword.get(opts, :relevance_score, 0.7),
      is_overruled: Keyword.get(opts, :is_overruled, false),
      spoiler_level: Keyword.get(opts, :spoiler_level, 0),
      inserted_at: now,
      updated_at: now
    }

    row =
      case Keyword.get(opts, :vndb_avg_score) do
        nil -> row
        score -> Map.put(row, :vndb_avg_score, score)
      end

    Repo.insert_all("vn_tags", [row])
  end

  defp insert_vn_title!(vn, lang, title) do
    Repo.insert_all("vn_titles", [
      %{
        id: Ecto.UUID.dump!(Ecto.UUID.generate()),
        visual_novel_id: Ecto.UUID.dump!(vn.id),
        lang: lang,
        title: title,
        official: true
      }
    ])
  end

  defp insert_vn_image!(vn, vndb_cv_id, opts) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert_all("vn_images", [
      %{
        id: Ecto.UUID.dump!(Ecto.UUID.generate()),
        visual_novel_id: Ecto.UUID.dump!(vn.id),
        vndb_cv_id: vndb_cv_id,
        width: Keyword.get(opts, :width, 800),
        height: Keyword.get(opts, :height, 1200),
        inserted_at: now,
        updated_at: now
      }
    ])
  end

  defp insert_vn_release!(vn, vndb_id, title) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert_all("vn_releases", [
      %{
        id: Ecto.UUID.dump!(Ecto.UUID.generate()),
        visual_novel_id: Ecto.UUID.dump!(vn.id),
        vndb_id: vndb_id,
        title: title,
        inserted_at: now,
        updated_at: now
      }
    ])
  end

  defp set_favorites!(user, vn_ids) do
    bin_ids = Enum.map(vn_ids, &Ecto.UUID.dump!/1)
    user_bin = Ecto.UUID.dump!(user.id)

    Repo.query!("UPDATE users SET favorite_visual_novels = $1::uuid[] WHERE id = $2::uuid", [
      bin_ids,
      user_bin
    ])
  end

  defp favorites(user) do
    {:ok, %{rows: [[arr]]}} =
      Repo.query("SELECT favorite_visual_novels FROM users WHERE id = $1::uuid", [
        Ecto.UUID.dump!(user.id)
      ])

    Enum.map(arr, fn bin -> Ecto.UUID.cast!(bin) end)
  end

  defp insert_vn_relation!(vn, related_vn, relation_type) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert_all("vn_relations", [
      %{
        visual_novel_id: Ecto.UUID.dump!(vn.id),
        related_vn_id: Ecto.UUID.dump!(related_vn.id),
        relation_type: relation_type,
        is_official: true,
        inserted_at: now,
        updated_at: now
      }
    ])
  end
end
