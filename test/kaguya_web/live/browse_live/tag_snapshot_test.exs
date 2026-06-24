defmodule KaguyaWeb.BrowseLive.TagSnapshotTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Kaguya.Repo
  alias Kaguya.Tags.Tag
  alias Kaguya.VisualNovels.VisualNovel
  alias Kaguya.VisualNovels.VNTag
  alias KaguyaWeb.BrowseLive.TagSnapshot

  setup do
    :ok = Sandbox.checkout(Repo)
    # The snapshot is global (persistent_term); start clean and clean up after.
    TagSnapshot.invalidate()
    on_exit(&TagSnapshot.invalidate/0)

    vn = insert_vn!()
    content = insert_tag!("time-travel", "Time Travel", category: :content, kind: :theme)
    sexual = insert_tag!("nukige", "Nukige", category: :sexual, kind: :genre)
    tag_vn!(vn, content)
    tag_vn!(vn, sexual)

    %{vn: vn, content: content, sexual: sexual}
  end

  test "list/0 excludes sexual tags, list(include_sexual: true) includes them",
       %{content: content, sexual: sexual} do
    browse = TagSnapshot.list()
    all = TagSnapshot.list(include_sexual: true)

    browse_slugs = Enum.map(browse, &Map.get(&1, "slug"))
    all_slugs = Enum.map(all, &Map.get(&1, "slug"))

    assert content.slug in browse_slugs
    refute sexual.slug in browse_slugs
    assert content.slug in all_slugs
    assert sexual.slug in all_slugs
  end

  test "shapes rows into the frontend JSON map: uppercase enums, vnsCount, no id",
       %{content: content} do
    tag = TagSnapshot.find(content.slug)

    assert tag["name"] == "Time Travel"
    assert tag["slug"] == content.slug
    assert tag["category"] == "CONTENT"
    assert tag["kind"] == "THEME"
    assert tag["contentWarning"] == false
    assert tag["vnsCount"] == 1
    refute Map.has_key?(tag, "id")
  end

  test "contentWarning: true tags carry the flag through to the JSON map", %{vn: vn} do
    cw = insert_tag!("cw", "CW Tag", category: :content, kind: :theme, content_warning: true)
    tag_vn!(vn, cw)
    TagSnapshot.invalidate()

    assert TagSnapshot.find(cw.slug)["contentWarning"] == true
  end

  test "served asset body is hashed JSON with the filtered (non-sexual) tags only",
       %{content: content, sexual: sexual} do
    body = TagSnapshot.asset_body()
    decoded = Jason.decode!(body)
    slugs = Enum.map(decoded, &Map.get(&1, "slug"))

    assert content.slug in slugs
    refute sexual.slug in slugs
    assert TagSnapshot.asset_path() == "/data/#{TagSnapshot.asset_hash()}/vn-tags.json"
  end

  test "title/1 returns the tag name, falling back to a humanized slug",
       %{content: content} do
    assert TagSnapshot.title(content.slug) == "Time Travel"
    assert TagSnapshot.title("some-unknown-tag") == "Some Unknown Tag"
  end

  test "invalidate/0 rebuilds the snapshot from the DB", %{vn: vn} do
    assert length(TagSnapshot.list(include_sexual: true)) == 2

    new_tag = insert_tag!("drama", "Drama", category: :content, kind: :genre)
    tag_vn!(vn, new_tag)

    # Stale until invalidated (persistent_term is held across reads).
    assert length(TagSnapshot.list(include_sexual: true)) == 2

    TagSnapshot.invalidate()
    assert length(TagSnapshot.list(include_sexual: true)) == 3
  end

  defp insert_vn!() do
    suffix = :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)

    %VisualNovel{}
    |> VisualNovel.changeset(%{title: "Snapshot Test #{suffix}", original_language: "en"})
    |> Repo.insert!()
  end

  defp insert_tag!(slug, name, attrs) do
    suffix = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)

    %Tag{}
    |> Tag.changeset(
      %{
        name: name,
        slug: "#{slug}-#{suffix}",
        vndb_tag_id: "g-test-#{suffix}"
      }
      |> Map.merge(Map.new(attrs))
    )
    |> Repo.insert!()
  end

  # Inserts a non-spoiler, non-overruled VN-tag association so the tag is
  # counted by VNTags.list_vn_tags/0.
  defp tag_vn!(vn, tag) do
    %VNTag{}
    |> VNTag.changeset(%{
      visual_novel_id: vn.id,
      tag_id: tag.id,
      vndb_vote_count: 3,
      vndb_avg_score: 2.5,
      spoiler_level: :none,
      is_overruled: false
    })
    |> Repo.insert!()
  end
end
