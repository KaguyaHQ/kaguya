defmodule KaguyaWeb.VNLive.HistoryTest do
  use KaguyaWeb.ConnCase, async: false

  alias Kaguya.Repo
  alias Kaguya.Revisions.Change
  alias Kaguya.Test.UserFixtures
  alias Kaguya.VisualNovels.VisualNovel

  test "renders absolute revision timestamps for history rows", %{conn: conn} do
    editor =
      UserFixtures.insert_user!(
        username: "vn_history_editor",
        display_name: "VN History Editor"
      )

    vn = insert_vn!("History VN", "history-vn")

    inserted_at = ~U[2026-04-28 17:10:00Z]

    revision =
      Repo.insert!(%Change{
        entity_type: :visual_novel,
        entity_id: vn.id,
        revision_number: 3,
        action: :edit,
        changed_fields: ["description"],
        summary: "Expanded synopsis",
        source: :user,
        user_id: editor.id,
        inserted_at: inserted_at
      })

    {:ok, view, html} = live(conn, ~p"/vn/#{vn.slug}/history")

    assert html =~ "History VN"
    assert html =~ "Expanded synopsis"
    assert html =~ "VN History Editor"
    assert html =~ "Apr 28, 2026 17:10"
    refute html =~ "ago"
    # Edit-history/diff pages are derivative with unbounded revision variants.
    assert html =~ ~s(<meta name="robots" content="noindex,follow")

    assert has_element?(view, "#vn-history-revision-#{revision.id}")
    assert has_element?(view, "#vn-history-revision-#{revision.id} a", "r3")
  end

  defp insert_vn!(title, slug) do
    suffix = System.unique_integer([:positive])

    Repo.insert!(%VisualNovel{
      title: "#{title} #{suffix}",
      slug: "#{slug}-#{suffix}",
      aliases: [],
      title_category: :vn
    })
  end
end
