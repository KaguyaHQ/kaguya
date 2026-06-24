defmodule KaguyaWeb.VNLive.PageDataTest do
  use KaguyaWeb.ConnCase, async: false

  alias Kaguya.Characters.Quote
  alias Kaguya.Releases.Release
  alias Kaguya.Repo
  alias Kaguya.Screenshots.Screenshot
  alias Kaguya.VisualNovels.{Image, VisualNovel}
  alias KaguyaWeb.VNLive.PageData

  test "tab loaders return normalized media and quotes for a VN" do
    vn = insert_vn!("page-data-tabs")

    cover_id = Ecto.UUID.generate()
    screenshot_id = Ecto.UUID.generate()

    Repo.insert!(%Image{
      id: cover_id,
      visual_novel_id: vn.id,
      language: "en",
      release_date: ~D[2020-01-01]
    })

    Repo.insert!(%Screenshot{
      id: screenshot_id,
      visual_novel_id: vn.id,
      is_nsfw: true
    })

    %Quote{}
    |> Quote.changeset(%{
      visual_novel_id: vn.id,
      quote: "The sky is still ours."
    })
    |> Repo.insert!()

    assert {:ok, [%{id: ^cover_id, language: "en"}]} = PageData.get_tab(vn.slug, :covers, nil)

    assert {:ok, [%{id: ^screenshot_id, is_nsfw: true}]} =
             PageData.get_tab(vn.slug, :screenshots, nil)

    assert {:ok, [%{quote: "The sky is still ours."}]} = PageData.get_tab(vn.slug, :quotes, nil)
  end

  test "release loader respects language and platform filters" do
    vn = insert_vn!("page-data-releases")

    insert_release!(vn, "Windows English Edition", ["en"], ["win"])
    insert_release!(vn, "Switch Japanese Edition", ["ja"], ["swi"])

    assert {:ok, %{items: [%{title: "Windows English Edition"}]}} =
             PageData.get_tab(vn.slug, :releases, nil, %{language: "en", platform: "win"})

    assert {:ok, %{items: [%{title: "Switch Japanese Edition"}]}} =
             PageData.get_tab(vn.slug, :releases, nil, %{language: "ja", platform: "swi"})

    assert {:ok, %{items: []}} =
             PageData.get_tab(vn.slug, :releases, nil, %{language: "en", platform: "swi"})
  end

  test "tab loader returns not_found for a missing VN" do
    assert {:error, :not_found} = PageData.get_tab("missing-vn", :covers, nil)
  end

  defp insert_vn!(slug) do
    %VisualNovel{}
    |> VisualNovel.changeset(%{
      title: String.replace(slug, "-", " "),
      slug: slug,
      description: "A" <> String.duplicate(" page data visual novel description", 3)
    })
    |> Repo.insert!()
  end

  defp insert_release!(vn, title, languages, platforms) do
    %Release{}
    |> Release.changeset(%{
      visual_novel_id: vn.id,
      title: title,
      languages: languages,
      platforms: platforms
    })
    |> Repo.insert!()
  end
end
