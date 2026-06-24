defmodule KaguyaWeb.ChangesLive.IndexTest do
  use KaguyaWeb.ConnCase, async: false

  alias Kaguya.Repo
  alias Kaguya.Revisions.Change
  alias Kaguya.Test.UserFixtures
  alias Kaguya.VisualNovels.VisualNovel

  test "renders recent user-authored changes with entity and user metadata", %{conn: conn} do
    user = UserFixtures.insert_user!(username: "edit_author", display_name: "Edit Author")
    vn = insert_vn!("Recent Change VN")

    insert_change!(vn, user, %{
      revision_number: 1,
      action: :edit,
      summary: "Expanded the synopsis",
      changed_fields: ["description", "titles"]
    })

    {:ok, _view, html} = live(conn, ~p"/history")

    assert html =~ "Recent changes"
    assert html =~ "Recent Change VN"
    assert html =~ "Edit Author"
    assert html =~ "Expanded the synopsis"
    assert html =~ "description, titles"
    assert html =~ ~s(href="/vn/#{vn.slug}")
  end

  test "filters changes by entity type", %{conn: conn} do
    user = UserFixtures.insert_user!(username: "filter_author")
    vn = insert_vn!("Visible VN Change")
    character = insert_character!("Filtered Character Change")

    insert_change!(vn, user, %{revision_number: 1, summary: "VN update"})

    insert_change!(character, user, %{
      revision_number: 1,
      entity_type: :character,
      summary: "Character update"
    })

    {:ok, _view, html} = live(conn, ~p"/history?type=visual_novel")

    assert html =~ "Visible VN Change"
    refute html =~ "Filtered Character Change"
  end

  test "renders pagination links", %{conn: conn} do
    user = UserFixtures.insert_user!(username: "page_author")

    for index <- 1..26 do
      vn = insert_vn!("Paged Change #{index}")
      insert_change!(vn, user, %{revision_number: 1, summary: "Paged edit #{index}"})
    end

    {:ok, _view, html} = live(conn, ~p"/history")

    assert html =~ "Page 1 of 2"
    assert html =~ ~s(href="/history?page=2")
  end

  defp insert_vn!(title) do
    suffix = System.unique_integer([:positive])

    %VisualNovel{}
    |> VisualNovel.changeset(%{
      title: "#{title} #{suffix}",
      original_language: "en",
      title_category: :vn,
      temp_image_url: "https://images.example/#{suffix}.jpg"
    })
    |> Repo.insert!()
  end

  defp insert_character!(name) do
    suffix = System.unique_integer([:positive])

    %Kaguya.Characters.Character{}
    |> Kaguya.Characters.Character.changeset(%{
      name: "#{name} #{suffix}",
      vndb_image_id: "ch#{suffix}"
    })
    |> Repo.insert!()
  end

  defp insert_change!(entity, user, attrs) do
    entity_type = Map.get(attrs, :entity_type, :visual_novel)

    %Change{}
    |> Change.changeset(%{
      entity_type: entity_type,
      entity_id: entity.id,
      revision_number: Map.get(attrs, :revision_number, 1),
      action: Map.get(attrs, :action, :edit),
      changed_fields: Map.get(attrs, :changed_fields, ["title"]),
      summary: Map.fetch!(attrs, :summary),
      source: :user,
      user_id: user.id
    })
    |> Repo.insert!()
  end
end
