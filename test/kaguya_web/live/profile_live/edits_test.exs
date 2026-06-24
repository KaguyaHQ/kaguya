defmodule KaguyaWeb.ProfileLive.EditsTest do
  use KaguyaWeb.ConnCase, async: false

  alias Kaguya.Producers.Producer
  alias Kaguya.Producers
  alias Kaguya.Repo
  alias Kaguya.Revisions
  alias Kaguya.Revisions.Change
  alias Kaguya.Test.UserFixtures
  alias Kaguya.VisualNovels
  alias Kaguya.VisualNovels.VisualNovel

  describe "GET /@:username/edits" do
    test "renders the empty edits tab with filters and heatmap" do
      _user = UserFixtures.insert_user!(username: "quiet_edits", display_name: "Quiet")

      {:ok, _view, html} = live(build_conn(), "/@quiet_edits/edits")

      assert html =~ "0"
      assert html =~ "contributions by Quiet"
      assert html =~ "last 30 days"
      assert html =~ "Visual novels"
      assert html =~ "Releases"
      assert html =~ "Producers"
      assert html =~ "Characters"
      assert html =~ "Series"
      assert html =~ "Quiet hasn&#39;t made any edits matching these filters."
      refute html =~ "coming soon"
    end

    test "renders revision rows, burst groups, entity links, and revision labels" do
      user = UserFixtures.insert_user!(username: "editor", display_name: "Editor")
      vn = insert_vn!("Grouped VN")
      base_time = utc_now()

      insert_change!(
        user,
        :visual_novel,
        vn.id,
        1,
        "Initial cleanup",
        DateTime.add(base_time, -5, :minute),
        changed_fields: ["description"]
      )

      insert_change!(user, :visual_novel, vn.id, 2, "Fixed title", base_time,
        changed_fields: ["title"]
      )

      {:ok, _view, html} = live(build_conn(), "/@editor/edits")

      assert html =~ "2"
      assert html =~ "contributions by Editor"
      assert html =~ "Grouped VN"
      assert html =~ "2 edits"
      assert html =~ "Initial cleanup"
      assert html =~ "Fixed title"
      assert html =~ ~s(href="/vn/#{vn.slug}")
      assert html =~ "r2"
    end

    test "renders inline diff content for an expanded fixture revision" do
      user = UserFixtures.insert_user!(username: "diff_editor", display_name: "Diffy")

      {:ok, %{entity: vn}} =
        Revisions.create_entity(
          :visual_novel,
          %{
            title: "Diff Fixture VN",
            description: "A quiet mystery with one ending.",
            original_language: "en",
            development_status: "in_development",
            length_category: "short",
            has_ero: false,
            aliases: ["old alias"]
          },
          "Created fixture",
          user
        )

      {:ok, change} =
        Revisions.submit_edit(
          :visual_novel,
          vn.id,
          %{
            description: "A bright mystery with two endings.",
            development_status: "finished",
            length_category: "medium",
            has_ero: true,
            aliases: ["old alias", "new alias"]
          },
          "Updated VN fields",
          user
        )

      {:ok, view, html} = live(build_conn(), "/@diff_editor/edits")

      assert html =~ "Updated VN fields"
      refute html =~ "A bright mystery with two endings."

      html = render_click(view, "toggle_revision_diff", %{"id" => change.id})

      assert html =~ "Description"
      assert html =~ "quiet"
      assert html =~ "bright"
      assert html =~ "Development status"
      assert html =~ "In development"
      assert html =~ "Finished"
      assert html =~ "Length"
      assert html =~ "Short (&lt; 2 hours)"
      assert html =~ "Medium (10–30 hours)"
      assert html =~ "Erotic content"
      assert html =~ "No"
      assert html =~ "Yes"
      assert html =~ "Aliases"
      assert html =~ "new alias"
    end

    test "filters revisions by entity type through the Next-compatible t param" do
      user = UserFixtures.insert_user!(username: "filtered", display_name: "Filtered")
      vn = insert_vn!("Filtered VN")
      producer = insert_producer!("Filtered Studio")
      base_time = utc_now()

      insert_change!(
        user,
        :visual_novel,
        vn.id,
        1,
        "VN edit",
        DateTime.add(base_time, -60, :second)
      )

      insert_change!(user, :producer, producer.id, 1, "Producer edit", base_time)

      {:ok, _view, html} = live(build_conn(), "/@filtered/edits?t=p")

      assert html =~ "2"
      assert html =~ "contributions by Filtered"
      assert html =~ "1"
      assert html =~ "last 30 days"
      assert html =~ "Filtered Studio"
      assert html =~ "Producer edit"
      refute html =~ "Filtered VN"
      refute html =~ "VN edit"
      assert html =~ ~s(href="/@filtered/edits")
      assert html =~ ~s(aria-pressed="true")
    end

    test "load_more_edits appends the next revision page" do
      user =
        UserFixtures.insert_user!(username: "prolific_edits", display_name: "Prolific")

      vn = insert_vn!("Long History VN")
      base_time = utc_now()

      for n <- 1..55 do
        insert_change!(
          user,
          :visual_novel,
          vn.id,
          n,
          if(n == 1, do: "Oldest page only", else: "Revision #{n}"),
          DateTime.add(base_time, n - 55, :hour)
        )
      end

      {:ok, view, html} = live(build_conn(), "/@prolific_edits/edits")

      assert html =~ "Load more"
      assert html =~ "Revision 55"
      refute html =~ "Oldest page only"

      html_after = render_click(view, "load_more_edits")

      assert html_after =~ "Oldest page only"
      refute html_after =~ "Load more"
    end
  end

  defp insert_change!(
         user,
         entity_type,
         entity_id,
         revision_number,
         summary,
         inserted_at,
         attrs \\ []
       ) do
    Repo.insert!(%Change{
      entity_type: entity_type,
      entity_id: entity_id,
      revision_number: revision_number,
      action: Keyword.get(attrs, :action, :edit),
      changed_fields: Keyword.get(attrs, :changed_fields, []),
      summary: summary,
      source: Keyword.get(attrs, :source, :user),
      user_id: user.id,
      inserted_at: inserted_at
    })
    |> write_revision_snapshot!()
  end

  defp write_revision_snapshot!(%Change{entity_type: :visual_novel} = change) do
    change.entity_id
    |> VisualNovels.get_for_edit()
    |> then(&VisualNovels.write_hist(change.id, &1))

    change
  end

  defp write_revision_snapshot!(%Change{entity_type: :producer} = change) do
    change.entity_id
    |> Producers.get_for_edit()
    |> then(&Producers.write_hist(change.id, &1))

    change
  end

  defp write_revision_snapshot!(change), do: change

  defp insert_vn!(title) do
    suffix = unique_suffix()

    %VisualNovel{}
    |> VisualNovel.changeset(%{title: "#{title} #{suffix}", original_language: "en"})
    |> Repo.insert!()
  end

  defp insert_producer!(name) do
    suffix = unique_suffix()

    %Producer{}
    |> Producer.changeset(%{name: "#{name} #{suffix}"})
    |> Repo.insert!()
  end

  defp unique_suffix do
    :crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower)
  end

  defp utc_now do
    DateTime.utc_now() |> DateTime.truncate(:second)
  end
end
