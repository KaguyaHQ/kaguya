defmodule KaguyaWeb.VNLive.ReleaseCreditsTest do
  use KaguyaWeb.ConnCase, async: false
  import Ecto.Query
  alias Kaguya.{Repo, Revisions}
  alias Kaguya.Producers.{Producer, VNProducer}
  alias Kaguya.Releases.{Release, Credits}
  alias Kaguya.VisualNovels.{VisualNovel, VNTitle, Contributions}
  alias KaguyaWeb.VNLive.Edit.ReleaseForm

  setup %{conn: conn} do
    user = Kaguya.Test.UserFixtures.insert_user!()
    conn = conn |> Plug.Test.init_test_session(%{}) |> KaguyaWeb.UserAuth.log_in_user(user)
    %{user: user, conn: conn}
  end

  test "creating an AVN saves its developer and initial release together", %{conn: conn} do
    producer = producer!("AVN Developer")
    {:ok, view, _} = live(conn, "/contribute/vn")
    view |> element("button[phx-value-mode=avn]") |> render_click()

    view
    |> element("form[phx-submit=continue_to_form]")
    |> render_submit(%{"title" => "Ongoing AVN"})

    key = release_key(view)
    add_producer(view, key, producer)
    assert has_element?(view, "#vn-release-#{key}", producer.name)

    assert {:error, {:live_redirect, %{to: "/vn/ongoing-avn"}}} =
             view
             |> element("#vn-edit-form")
             |> render_submit(%{"vn" => %{"summary" => "Create ongoing work"}})

    vn = Repo.get_by!(VisualNovel, slug: "ongoing-avn")
    assert vn.is_avn
    release = Repo.get_by!(Release, visual_novel_id: vn.id)
    assert release.title == vn.title
    assert release.producers == [credit(producer, true, false)]
    assert Repo.get_by!(VNProducer, visual_novel_id: vn.id).producer_id == producer.id
    assert Revisions.latest_revision_number(:release, release.id) == 1
  end

  test "credits are edited on the selected release and can be reverted", %{conn: conn, user: user} do
    vn = vn!()
    dev = producer!("Original Developer")
    publisher = producer!("English Publisher")
    original = release!(vn, "Original", [credit(dev, true, false)], ~D[2020-01-01])
    english = release!(vn, "English", [], ~D[2021-02-03])
    {:ok, view, _} = live(conn, "/vn/#{vn.slug}/edit")
    add_producer(view, english.id, publisher)
    role_id = credit_key(view, english.id)

    view
    |> element("#vn-edit-form")
    |> render_change(%{
      "vn" => %{
        "releases" => %{english.id => %{"producers" => %{role_id => %{"role" => "publisher"}}}}
      }
    })

    view
    |> element("#vn-edit-form")
    |> render_submit(%{"vn" => %{"summary" => "Credit English publisher"}})

    assert Repo.get!(Release, original.id).producers == original.producers
    assert Repo.get!(Release, english.id).producers == [credit(publisher, false, true)]

    assert Repo.get_by!(VNProducer, visual_novel_id: vn.id, producer_id: dev.id).earliest_release_date ==
             ~D[2020-01-01]

    baseline =
      Repo.one!(
        from(c in Kaguya.Revisions.Change,
          where: c.entity_id == ^english.id and c.revision_number == 1
        )
      )

    assert {:ok, _} = Revisions.revert_to_revision(baseline.id, "Undo publisher credit", user)
    assert Repo.get!(Release, english.id).producers == []
    refute Repo.get_by(VNProducer, visual_novel_id: vn.id, producer_id: publisher.id)
  end

  test "invalid dates and stale releases roll back the whole contribution", %{user: user} do
    vn = vn!()
    release = release!(vn, "Original", [], nil)
    bad = %{id: release.id, base_revision: 0, attrs: %{release_date: "not-a-date"}}

    assert {:error, _} =
             Contributions.update(
               vn.id,
               %{description: "Must roll back"},
               [bad],
               "Bad date",
               user,
               0
             )

    assert Repo.get!(VisualNovel, vn.id).description == vn.description
    assert Revisions.latest_revision_number(:visual_novel, vn.id) == 0

    assert {:ok, _} =
             Revisions.submit_edit(
               :release,
               release.id,
               %{title: "Updated"},
               "Other editor",
               user
             )

    stale = %{id: release.id, base_revision: 0, attrs: %{title: "Stale title"}}

    assert {:error, :edit_conflict} =
             Contributions.update(vn.id, %{}, [stale], "Stale edit", user, 0)

    assert Repo.get!(Release, release.id).title == "Updated"
  end

  test "unavailable producers and foreign or locked releases cannot be edited", %{user: user} do
    vn = vn!()

    hidden =
      producer!("Hidden")
      |> Ecto.Changeset.change(hidden_at: DateTime.utc_now() |> DateTime.truncate(:second))
      |> Repo.update!()

    local = release!(vn, "Original", [], nil)
    foreign = release!(vn!(), "Other VN", [], nil)

    for edit <- [
          %{id: foreign.id, base_revision: 0, attrs: %{title: "Wrong parent"}},
          %{id: local.id, base_revision: 0, attrs: %{producers: [credit(hidden, true, false)]}}
        ] do
      assert {:error, _} = Contributions.update(vn.id, %{}, [edit], "Invalid edit", user, 0)
    end

    local |> Ecto.Changeset.change(is_locked: true) |> Repo.update!()

    assert {:error, _} =
             Contributions.update(
               vn.id,
               %{},
               [%{id: local.id, base_revision: 0, attrs: %{title: "Locked"}}],
               "Locked edit",
               user,
               0
             )

    assert Repo.get!(Release, local.id).title == "Original"
  end

  test "recomputing from stored releases keeps local edits and matches imported role names" do
    vn = vn!()

    producer =
      producer!("Imported Studio") |> Ecto.Changeset.change(vndb_id: "p999998") |> Repo.update!()

    release =
      release!(
        vn,
        "Imported",
        [
          %{
            "vndb_id" => producer.vndb_id,
            "name" => producer.name,
            "developer" => true,
            "publisher" => true
          }
        ],
        ~D[2022-01-01]
      )

    assert :ok = Credits.recompute([vn.id])
    assert Repo.get_by!(VNProducer, visual_novel_id: vn.id).role == "developer_publisher"
    release |> Ecto.Changeset.change(producers: []) |> Repo.update!()
    assert :ok = Credits.recompute([vn.id])
    refute Repo.get_by(VNProducer, visual_novel_id: vn.id)
  end

  test "editing an ongoing version updates one release, preserving other metadata", %{conn: conn} do
    vn = vn!()

    release =
      release!(vn, "Version 0.8", [], nil)
      |> Ecto.Changeset.change(platforms: ["win"], notes: "Preserve notes", vndb_id: "r999999")
      |> Repo.update!()

    {:ok, view, _} = live(conn, "/vn/#{vn.slug}/edit")

    view
    |> element("#vn-edit-form")
    |> render_submit(%{
      "vn" => %{
        "summary" => "Update ongoing version",
        "releases" => %{release.id => %{"title" => "Version 0.9"}}
      }
    })

    updated = Repo.get!(Release, release.id)
    assert updated.title == "Version 0.9"
    assert updated.platforms == ["win"]
    assert updated.notes == "Preserve notes"
    assert Repo.aggregate(from(r in Release, where: r.visual_novel_id == ^vn.id), :count) == 1
  end

  test "producer searches ignore hidden entries and edits do not accept forged identities", %{
    conn: conn,
    user: user
  } do
    vn = vn!()
    producer = producer!("Visible Studio")

    hidden =
      producer!("Visible Hidden")
      |> Ecto.Changeset.change(hidden_at: DateTime.utc_now() |> DateTime.truncate(:second))
      |> Repo.update!()

    release = release!(vn, "Original", [credit(producer, true, false)], nil)
    {:ok, view, _} = live(conn, "/vn/#{vn.slug}/edit")

    view
    |> element("#producer-search-#{release.id}")
    |> render_change(%{"producer_query" => "Visible", "release" => release.id})

    refute has_element?(view, "#add-producer-#{release.id}-#{hidden.id}")
    [form] = ReleaseForm.load(vn.id, user)
    [row] = form["producers"]

    [normalized] =
      ReleaseForm.normalize(
        %{
          release.id => %{
            "producers" => %{
              row["key"] => %{
                "producer_id" => hidden.id,
                "name" => "Forged",
                "role" => "publisher"
              }
            }
          }
        },
        [form]
      )

    assert hd(normalized["producers"])["data"]["producer_id"] == producer.id
  end

  test "unresolved producer references cannot borrow a local producer's identity" do
    vn = vn!()
    producer = producer!("Local creator")
    unknown = %{"producer_id" => UUIDv7.generate(), "developer" => false, "publisher" => true}
    release!(vn, "Local release", [credit(producer, true, false), unknown], nil)
    assert :ok = Credits.recompute([vn.id])
    assert Repo.get_by!(VNProducer, visual_novel_id: vn.id).role == "developer"
  end

  defp vn! do
    suffix = System.unique_integer([:positive])

    vn =
      Repo.insert!(%VisualNovel{
        title: "Credits VN #{suffix}",
        slug: "credits-vn-#{suffix}",
        original_language: "en"
      })

    Repo.insert!(%VNTitle{visual_novel_id: vn.id, title: vn.title, lang: "en", official: true})
    vn
  end

  defp producer!(name),
    do:
      Repo.insert!(%Producer{name: name, slug: "producer-#{System.unique_integer([:positive])}"})

  defp release!(vn, title, producers, date),
    do:
      Repo.insert!(%Release{
        visual_novel_id: vn.id,
        title: title,
        producers: producers,
        release_date: date
      })

  defp credit(p, dev, pub),
    do: %{"producer_id" => p.id, "name" => p.name, "developer" => dev, "publisher" => pub}

  defp release_key(view),
    do:
      render(view)
      |> LazyHTML.from_document()
      |> LazyHTML.query("[id^=vn-release-]")
      |> LazyHTML.attribute("id")
      |> hd()
      |> String.replace_prefix("vn-release-", "")

  defp credit_key(view, release),
    do:
      render(view)
      |> LazyHTML.from_document()
      |> LazyHTML.query("#vn-release-#{release} [id^=credit-role-]")
      |> LazyHTML.attribute("id")
      |> hd()
      |> String.replace_prefix("credit-role-", "")

  defp add_producer(view, key, producer) do
    view
    |> element("#producer-search-#{key}")
    |> render_change(%{"producer_query" => producer.name, "release" => key})

    view |> element("#add-producer-#{key}-#{producer.id}") |> render_click()
  end
end
