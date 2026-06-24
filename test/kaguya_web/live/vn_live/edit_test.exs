defmodule KaguyaWeb.VNLive.EditTest do
  use KaguyaWeb.ConnCase, async: false
  import Ecto.Query

  alias Kaguya.Repo
  alias Kaguya.Revisions
  alias Kaguya.Screenshots.Screenshot
  alias Kaguya.Users.User
  alias Kaguya.VisualNovels.{Image, Relation, VNTitle, VisualNovel}
  alias KaguyaWeb.UserAuth

  setup do
    previous = Application.get_env(:kaguya, :upload_req_options)

    Req.Test.stub(:upload_staging, fn conn ->
      Plug.Conn.send_resp(conn, 200, "")
    end)

    Application.put_env(:kaguya, :upload_req_options, plug: {Req.Test, :upload_staging})

    on_exit(fn ->
      if previous do
        Application.put_env(:kaguya, :upload_req_options, previous)
      else
        Application.delete_env(:kaguya, :upload_req_options)
      end
    end)

    :ok
  end

  test "renders auth prompt for anonymous viewers", %{conn: conn} do
    vn = insert_vn!("Anon VN", "anon-vn")

    {:ok, _view, html} = live(conn, ~p"/vn/#{vn.slug}/edit")

    assert html =~ "Sign in to edit this visual novel."
  end

  test "submits vn edits from the titles and general sections", %{conn: conn} do
    vn = insert_vn!("Original VN", "original-vn")
    insert_title!(vn, "ja", "Original VN")
    user = insert_user!()

    {:ok, view, _html} =
      conn
      |> log_in(user)
      |> live(~p"/vn/#{vn.slug}/edit")

    expected_path = "/vn/#{vn.slug}"

    assert {:error, {:live_redirect, %{to: ^expected_path}}} =
             view
             |> element("form#vn-edit-form")
             |> render_submit(%{
               "vn" => %{
                 "description" => "Updated description",
                 "aliases" => "Alias One\nAlias Two",
                 "development_status" => "finished",
                 "length_category" => "long",
                 "original_language" => "ja",
                 "release_date" => "2024-12-13",
                 "min_age" => "18",
                 "has_ero" => "true",
                 "is_avn" => "false",
                 "title_category" => "vn",
                 "summary" => "Updated core VN fields",
                 "titles" => %{
                   "0" => %{
                     "lang" => "ja",
                     "title" => "Mahoutsukai no Yoru",
                     "latin" => "Mahoutsukai no Yoru",
                     "official" => "true"
                   }
                 }
               }
             })

    updated = Repo.get!(VisualNovel, vn.id)
    assert updated.description == "Updated description"
    assert updated.aliases == ["Alias One", "Alias Two"]
    assert updated.development_status == "finished"
    assert updated.length_category == "long"
    assert updated.original_language == "ja"
    assert updated.release_date == ~D[2024-12-13]
    assert updated.min_age == 18
    assert updated.has_ero == true
    assert updated.is_avn == false

    titles =
      Repo.all(
        from t in VNTitle,
          where: t.visual_novel_id == ^vn.id,
          order_by: [asc: t.lang, asc: t.title],
          select: {t.lang, t.title, t.latin, t.official}
      )

    assert titles == [{"ja", "Mahoutsukai no Yoru", "Mahoutsukai no Yoru", true}]
  end

  test "submits relations and media edits", %{conn: conn} do
    vn = insert_vn!("Media VN", "media-vn")
    related = insert_vn!("Related VN", "related-vn")
    other = insert_vn!("Other VN", "other-vn")
    insert_title!(vn, "ja", "Media VN")
    user = insert_user!()

    cover_a = insert_cover!(vn, false)
    cover_b = insert_cover!(vn, true)
    screenshot = insert_screenshot!(vn, false, false)
    insert_relation!(vn, related, "sequel", true)

    {:ok, view, _html} =
      conn
      |> log_in(user)
      |> live(~p"/vn/#{vn.slug}/edit")

    expected_path = "/vn/#{vn.slug}"

    view
    |> element("button[phx-click='remove_cover'][phx-value-id='#{cover_a.id}']")
    |> render_click()

    view
    |> element("button[phx-click='remove_screenshot'][phx-value-id='#{screenshot.id}']")
    |> render_click()

    assert {:error, {:live_redirect, %{to: ^expected_path}}} =
             view
             |> element("form#vn-edit-form")
             |> render_submit(%{
               "vn" => %{
                 "description" => "",
                 "aliases" => "",
                 "development_status" => "",
                 "length_category" => "",
                 "original_language" => "",
                 "release_date" => "",
                 "min_age" => "",
                 "has_ero" => "false",
                 "is_avn" => "false",
                 "title_category" => "vn",
                 "primary_cover_id" => cover_b.id,
                 "summary" => "Updated relations and media",
                 "titles" => %{
                   "0" => %{
                     "lang" => "ja",
                     "title" => "Media VN",
                     "latin" => "",
                     "official" => "true"
                   }
                 },
                 "relations" => %{
                   "0" => %{
                     "related_vn_id" => other.id,
                     "related_vn_slug" => other.slug,
                     "related_vn_title" => other.title,
                     "relation_type" => "same_setting",
                     "is_official" => "false"
                   }
                 },
                 "screenshots" => %{
                   "0" => %{
                     "id" => screenshot.id,
                     "thumbnail_url" => "/screenshots/#{screenshot.id}",
                     "is_nsfw" => "true",
                     "is_brutal" => "true"
                   }
                 },
                 "covers" => %{
                   "0" => %{
                     "id" => cover_b.id,
                     "thumbnail_url" => "/covers/#{cover_b.id}",
                     "is_image_nsfw" => "false"
                   }
                 }
               }
             })

    updated_vn = Repo.get!(VisualNovel, vn.id)
    assert updated_vn.primary_image_id == cover_b.id

    relations =
      Repo.all(
        from r in Relation,
          where: r.visual_novel_id == ^vn.id,
          select: {r.related_vn_id, r.relation_type, r.is_official}
      )

    assert relations == [{other.id, "same_setting", false}]

    reverse_relations =
      Repo.all(
        from r in Relation,
          where: r.visual_novel_id == ^other.id,
          select: {r.related_vn_id, r.relation_type, r.is_official}
      )

    assert reverse_relations == [{vn.id, "same_setting", false}]

    assert Repo.get(Screenshot, screenshot.id) == nil
    assert Repo.get(Image, cover_a.id) == nil

    assert Repo.get!(Image, cover_b.id)

    assert Repo.get_by(Relation, visual_novel_id: related.id, related_vn_id: vn.id) == nil
  end

  test "adds new screenshots and covers from uploads", %{conn: conn} do
    vn = insert_vn!("Upload VN", "upload-vn")
    insert_title!(vn, "ja", "Upload VN")
    user = insert_user!()

    {:ok, view, _html} =
      conn
      |> log_in(user)
      |> live(~p"/vn/#{vn.slug}/edit")

    screenshot_upload =
      file_input(view, "#vn-edit-form", :new_screenshots, [
        %{
          last_modified: 1_714_000_000_000,
          name: "shot.png",
          content: png_binary(),
          type: "image/png"
        }
      ])

    assert render_upload(screenshot_upload, "shot.png") =~ "shot.png"

    cover_upload =
      file_input(view, "#vn-edit-form", :new_covers, [
        %{
          last_modified: 1_714_000_000_000,
          name: "cover.png",
          content: png_binary(),
          type: "image/png"
        }
      ])

    assert render_upload(cover_upload, "cover.png") =~ "cover.png"

    expected_path = "/vn/#{vn.slug}"

    assert {:error, {:live_redirect, %{to: ^expected_path}}} =
             view
             |> element("form#vn-edit-form")
             |> render_submit(%{
               "vn" => %{
                 "description" => "",
                 "aliases" => "",
                 "development_status" => "",
                 "length_category" => "",
                 "original_language" => "",
                 "release_date" => "",
                 "min_age" => "",
                 "has_ero" => "false",
                 "is_avn" => "false",
                 "title_category" => "vn",
                 "summary" => "Added uploaded images",
                 "titles" => %{
                   "0" => %{
                     "lang" => "ja",
                     "title" => "Upload VN",
                     "latin" => "",
                     "official" => "true"
                   }
                 }
               }
             })

    assert 1 ==
             Repo.aggregate(
               from(s in Screenshot, where: s.visual_novel_id == ^vn.id),
               :count,
               :id
             )

    assert 1 ==
             Repo.aggregate(
               from(i in Image, where: i.visual_novel_id == ^vn.id),
               :count,
               :id
             )

    assert Repo.get!(VisualNovel, vn.id).primary_image_id
  end

  test "shows no-op message when no changes are detected", %{conn: conn} do
    vn = insert_vn!("No-op VN", "no-op-vn")
    insert_title!(vn, "ja", "No-op VN")
    user = insert_user!()

    {:ok, view, _html} =
      conn
      |> log_in(user)
      |> live(~p"/vn/#{vn.slug}/edit")

    html =
      view
      |> element("form#vn-edit-form")
      |> render_submit(%{
        "vn" => %{
          "summary" => "No-op save",
          "titles" => %{
            "0" => %{
              "lang" => "ja",
              "title" => "No-op VN",
              "latin" => "",
              "official" => "true"
            }
          }
        }
      })

    assert html =~ "No changes detected."
  end

  test "updates base revision and reports conflict on stale edits", %{conn: conn} do
    user = insert_user!()
    vn = insert_vn!("Conflict VN", "conflict-vn")
    insert_title!(vn, "ja", "Conflict VN")

    {:ok, view, _html} =
      conn
      |> log_in(user)
      |> live(~p"/vn/#{vn.slug}/edit")

    {:ok, _change} =
      Revisions.submit_edit(
        :visual_novel,
        vn.id,
        %{description: "External change"},
        "External conflict edit",
        user
      )

    expected_revision = Revisions.latest_revision_number(:visual_novel, vn.id)

    html =
      view
      |> element("form#vn-edit-form")
      |> render_submit(%{
        "vn" => %{
          "description" => "Edited while stale",
          "summary" => "Concurrent conflict test",
          "titles" => %{
            "0" => %{
              "lang" => "ja",
              "title" => "Conflict VN",
              "latin" => "",
              "official" => "true"
            }
          }
        }
      })

    assert html =~ "This page was updated by someone else. Review your edits and submit again."
    assert expected_revision == Revisions.latest_revision_number(:visual_novel, vn.id)

    view
    |> element("form#vn-edit-form")
    |> render_submit(%{
      "vn" => %{
        "description" => "Retry after conflict",
        "summary" => "Retry after stale revision",
        "titles" => %{
          "0" => %{
            "lang" => "ja",
            "title" => "Conflict VN",
            "latin" => "",
            "official" => "true"
          }
        }
      }
    })

    assert_redirected(view, "/vn/#{vn.slug}")
  end

  test "preserves form values and surfaces upload error on upload failure", %{conn: conn} do
    previous = Application.get_env(:kaguya, :upload_req_options)

    try do
      Req.Test.stub(:upload_staging, fn conn ->
        Plug.Conn.send_resp(conn, 500, "")
      end)

      Application.put_env(:kaguya, :upload_req_options, plug: {Req.Test, :upload_staging})

      user = insert_user!()
      vn = insert_vn!("Upload Failure VN", "upload-failure-vn")
      insert_title!(vn, "ja", "Upload Failure VN")

      {:ok, view, _html} =
        conn
        |> log_in(user)
        |> live(~p"/vn/#{vn.slug}/edit")

      screenshot_upload =
        file_input(view, "#vn-edit-form", :new_screenshots, [
          %{
            last_modified: 1_714_000_000_000,
            name: "shot.png",
            content: png_binary(),
            type: "image/png"
          }
        ])

      assert render_upload(screenshot_upload, "shot.png") =~ "shot.png"

      html =
        view
        |> element("form#vn-edit-form")
        |> render_submit(%{
          "vn" => %{
            "description" => "Upload that fails",
            "summary" => "Upload failure preserved",
            "titles" => %{
              "0" => %{
                "lang" => "ja",
                "title" => "Upload Failure VN",
                "latin" => "",
                "official" => "true"
              }
            }
          }
        })

      assert html =~ "Upload failed with status 500"
      assert html =~ "Upload that fails"
      assert html =~ "Upload failure preserved"
    after
      if previous do
        Application.put_env(:kaguya, :upload_req_options, previous)
      else
        Application.delete_env(:kaguya, :upload_req_options)
      end
    end
  end

  test "blocks editing for locked entries", %{conn: conn} do
    user = insert_user!()
    vn = insert_vn!("Locked VN", "locked-vn", is_locked: true)

    {:ok, view, html} =
      conn
      |> log_in(user)
      |> live(~p"/vn/#{vn.slug}/edit")

    assert html =~ "This entry is locked for editing."
    refute has_element?(view, "form#vn-edit-form")
  end

  test "blocks editing for users without editing permission", %{conn: conn} do
    user = insert_user!(can_edit: false)
    vn = insert_vn!("Forbidden VN", "forbidden-vn")
    insert_title!(vn, "ja", "Forbidden VN")

    {:ok, view, html} =
      conn
      |> log_in(user)
      |> live(~p"/vn/#{vn.slug}/edit")

    assert html =~ "Your editing privileges have been revoked."
    refute has_element?(view, "form#vn-edit-form")
  end

  test "renders auth prompt for anonymous viewers on the create page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/contribute/vn")

    assert html =~ "Sign in to add a visual novel."
  end

  test "blocks creating for users without editing permission", %{conn: conn} do
    user = insert_user!(can_edit: false)

    {:ok, view, html} =
      conn
      |> log_in(user)
      |> live(~p"/contribute/vn")

    assert html =~ "You do not have permission to add a visual novel."
    refute has_element?(view, "form#vn-edit-form")
  end

  test "create page opens on the type-selection fork, not the form", %{conn: conn} do
    user = insert_user!()

    {:ok, view, html} =
      conn
      |> log_in(user)
      |> live(~p"/contribute/vn")

    assert html =~ "What kind of VN is this?"
    assert html =~ "Western AVN"
    refute has_element?(view, "form#vn-edit-form")
  end

  test "selecting AVN mode pre-fills the form with AVN defaults", %{conn: conn} do
    user = insert_user!()

    {:ok, view, _html} =
      conn
      |> log_in(user)
      |> live(~p"/contribute/vn")

    view |> element(~s(button[phx-value-mode="avn"])) |> render_click()

    html =
      view
      |> element(~s(form[phx-submit="continue_to_form"]))
      |> render_submit(%{"title" => "Eternum Test"})

    # The form step now renders, pre-filled from the AVN branch: title
    # carried over, is_avn flagged, English original language.
    assert has_element?(view, "form#vn-edit-form")
    assert html =~ "Eternum Test"
    assert has_element?(view, ~s(input[name="vn[is_avn]"][checked]))
    assert has_element?(view, ~s(option[value="en"][selected]))
  end

  test "creates a visual novel through the fork and form", %{conn: conn} do
    user = insert_user!()

    {:ok, view, _html} =
      conn
      |> log_in(user)
      |> live(~p"/contribute/vn")

    # The form is gated behind the type-fork step.
    refute has_element?(view, "form#vn-edit-form")

    view |> element(~s(button[phx-value-mode="other"])) |> render_click()

    view
    |> element(~s(form[phx-submit="continue_to_form"]))
    |> render_submit(%{"title" => "Created Test VN"})

    assert has_element?(view, "form#vn-edit-form")

    expected_path = "/vn/created-test-vn"

    assert {:error, {:live_redirect, %{to: ^expected_path}}} =
             view
             |> element("form#vn-edit-form")
             |> render_submit(%{
               "vn" => %{
                 "description" => "A freshly created entry",
                 "aliases" => "Alt One",
                 "development_status" => "finished",
                 "length_category" => "medium",
                 "original_language" => "en",
                 "release_date" => "2025-01-02",
                 "min_age" => "18",
                 "has_ero" => "false",
                 "is_avn" => "false",
                 "title_category" => "vn",
                 "summary" => "Initial creation",
                 "titles" => %{
                   "0" => %{
                     "lang" => "en",
                     "title" => "Created Test VN",
                     "latin" => "",
                     "official" => "true"
                   }
                 }
               }
             })

    created = Repo.get_by!(VisualNovel, slug: "created-test-vn")
    assert created.title == "Created Test VN"
    assert created.description == "A freshly created entry"
    assert created.aliases == ["Alt One"]
    assert created.development_status == "finished"
    assert created.length_category == "medium"
    assert created.original_language == "en"
    assert created.release_date == ~D[2025-01-02]
    assert created.min_age == 18

    titles =
      Repo.all(
        from t in VNTitle,
          where: t.visual_novel_id == ^created.id,
          select: {t.lang, t.title}
      )

    assert titles == [{"en", "Created Test VN"}]
  end

  defp insert_vn!(title, slug) do
    Repo.insert!(%VisualNovel{
      title: title,
      slug: slug,
      aliases: [],
      title_category: :vn
    })
  end

  defp insert_title!(vn, lang, title) do
    Repo.insert!(%VNTitle{
      visual_novel_id: vn.id,
      lang: lang,
      title: title,
      official: true
    })
  end

  defp insert_relation!(vn, related, relation_type, is_official) do
    Repo.insert!(%Relation{
      visual_novel_id: vn.id,
      related_vn_id: related.id,
      relation_type: relation_type,
      is_official: is_official
    })

    Repo.insert!(%Relation{
      visual_novel_id: related.id,
      related_vn_id: vn.id,
      relation_type: (relation_type == "sequel" && "prequel") || relation_type,
      is_official: is_official
    })
  end

  defp insert_cover!(vn, is_nsfw) do
    Repo.insert!(%Image{
      id: Ecto.UUID.generate(),
      visual_novel_id: vn.id,
      is_image_nsfw: is_nsfw
    })
  end

  defp insert_screenshot!(vn, is_nsfw, is_brutal) do
    Repo.insert!(%Screenshot{
      id: Ecto.UUID.generate(),
      visual_novel_id: vn.id,
      is_nsfw: is_nsfw,
      is_brutal: is_brutal,
      s3_key: "visual_novels/screenshots/#{Ecto.UUID.generate()}"
    })
  end

  defp insert_vn!(title, slug, attrs) when is_list(attrs) do
    Repo.insert!(
      Map.merge(
        %VisualNovel{
          title: title,
          slug: slug,
          aliases: [],
          title_category: :vn
        },
        Enum.into(attrs, %{})
      )
    )
  end

  defp insert_user!(opts \\ []) when is_list(opts) do
    can_edit = Keyword.get(opts, :can_edit, true)

    suffix = System.unique_integer([:positive])

    user =
      %User{}
      |> User.create_changeset(%{
        id: Ecto.UUID.generate(),
        username: "vn_edit_user_#{suffix}",
        display_name: "VN Editor #{suffix}",
        email: "vn-edit-#{suffix}@example.com"
      })
      |> Repo.insert!()

    if can_edit do
      user
    else
      Repo.update!(Ecto.Changeset.change(user, can_edit: false))
    end
  end

  defp log_in(conn, %User{} = user) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> UserAuth.log_in_user(user)
  end

  defp png_binary do
    Base.decode64!(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9WnQw1sAAAAASUVORK5CYII="
    )
  end
end
