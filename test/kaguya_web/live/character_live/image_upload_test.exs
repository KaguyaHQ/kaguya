defmodule KaguyaWeb.CharacterLive.ImageUploadTest do
  use KaguyaWeb.ConnCase, async: false

  import Ecto.Query

  alias Kaguya.Characters.{Character, CharacterImage, Contributions}
  alias Kaguya.Repo
  alias Kaguya.Revisions
  alias Kaguya.Revisions.Hist.{CharacterHist, CharacterImageHist}
  alias Kaguya.Test.UserFixtures
  alias Kaguya.Users.User
  alias KaguyaWeb.UserAuth

  setup %{conn: conn} do
    previous = Application.get_env(:kaguya, :upload_req_options)
    test_pid = self()

    Req.Test.stub(:character_image_staging, fn conn ->
      send(test_pid, :image_staged)
      Plug.Conn.send_resp(conn, 200, "")
    end)

    Application.put_env(:kaguya, :upload_req_options, plug: {Req.Test, :character_image_staging})

    on_exit(fn ->
      if previous,
        do: Application.put_env(:kaguya, :upload_req_options, previous),
        else: Application.delete_env(:kaguya, :upload_req_options)
    end)

    user = UserFixtures.insert_user!()
    conn = conn |> Plug.Test.init_test_session(%{}) |> UserAuth.log_in_user(user)
    %{conn: conn, user: user}
  end

  test "creates a character with an attributed image, content flags, processing job and history",
       %{
         conn: conn,
         user: user
       } do
    {:ok, view, _} = live(conn, ~p"/contribute/character")
    upload_image(view)
    assert has_element?(view, "#character-edit[data-dirty=true]")
    assert has_element?(view, "img[alt='Selected character image']")

    render_submit(element(view, "#character-edit"), %{
      "character" => %{"name" => "Portrait Heroine", "image_nsfw" => "true"}
    })

    character = Repo.get_by!(Character, name: "Portrait Heroine")
    assert_redirect(view, "/character/#{character.slug}")
    image = Repo.get!(CharacterImage, character.primary_image_id)
    assert image.character_id == character.id
    assert image.uploaded_by == user.id
    assert image.is_image_nsfw
    assert character.is_image_nsfw
    assert processing_jobs(image.id) == 1
    assert Repo.one!(from(h in CharacterHist, select: h.primary_image_id)) == image.id
    assert Repo.one!(from(h in CharacterImageHist, select: h.image_id)) == image.id
  end

  test "image-only replacement keeps the old image and can be reverted", %{conn: conn, user: user} do
    {character, initial} = character_with_image(user)
    previous_image = character.primary_image_id
    {:ok, view, _} = live(conn, ~p"/character/#{character.slug}/edit")
    assert has_element?(view, "#character-image-editor", "Replace image")
    upload_image(view)

    render_submit(element(view, "#character-edit"), %{
      "character" => %{"summary" => "Better portrait", "image_suggestive" => "true"}
    })

    updated = Repo.get!(Character, character.id)
    assert updated.primary_image_id != previous_image
    assert updated.is_image_suggestive
    assert Repo.get!(CharacterImage, previous_image)

    assert Repo.aggregate(
             from(i in CharacterImage, where: i.character_id == ^character.id),
             :count
           ) == 2

    assert Revisions.latest_revision_number(:character, character.id) == 2
    assert processing_jobs(updated.primary_image_id) == 1

    assert {:ok, _} = Revisions.revert_to_revision(initial.id, "Restore portrait", user)
    restored = Repo.get!(Character, character.id)
    assert restored.primary_image_id == previous_image
    refute restored.is_image_suggestive
  end

  test "cancelling a selection restores a clean form without saving an image", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/contribute/character")
    upload_image(view)
    render_change(element(view, "#character-edit"), %{"character" => %{"image_nsfw" => "true"}})
    render_click(element(view, "#character-image-editor button[phx-click=cancel_image]"))
    assert has_element?(view, "#character-edit[data-dirty=false]")
    refute has_element?(view, "img[alt='Selected character image']")
    assert Repo.aggregate(CharacterImage, :count) == 0
    refute_received :image_staged
  end

  test "a failed save keeps the selection and retries the staged image only once", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/contribute/character")
    upload_image(view)
    render_submit(element(view, "#character-edit"), %{"character" => %{"name" => ""}})
    assert_receive :image_staged
    assert has_element?(view, "img[alt='Selected character image']")
    assert Repo.aggregate(Character, :count) == 0
    assert Repo.aggregate(CharacterImage, :count) == 0
    assert Repo.aggregate(Oban.Job, :count) == 0

    render_submit(element(view, "#character-edit"), %{
      "character" => %{"name" => "Retry Portrait"}
    })

    character = Repo.get_by!(Character, name: "Retry Portrait")
    assert Repo.get!(CharacterImage, character.primary_image_id)
    refute_received :image_staged
  end

  test "invalid image bytes cannot replace the existing portrait", %{conn: conn, user: user} do
    {character, _} = character_with_image(user)
    {:ok, view, _} = live(conn, ~p"/character/#{character.slug}/edit")
    upload_image(view, "not an image")

    render_submit(element(view, "#character-edit"), %{
      "character" => %{"description" => "Should not save"}
    })

    assert Repo.get!(Character, character.id).primary_image_id == character.primary_image_id
    assert Repo.get!(Character, character.id).description == character.description
    assert Revisions.latest_revision_number(:character, character.id) == 1
    refute_received :image_staged
  end

  test "a storage failure keeps the existing portrait and selected file", %{
    conn: conn,
    user: user
  } do
    {character, _} = character_with_image(user)
    Req.Test.stub(:character_image_staging, &Plug.Conn.send_resp(&1, 503, ""))
    {:ok, view, _} = live(conn, ~p"/character/#{character.slug}/edit")
    upload_image(view)
    render_submit(element(view, "#character-edit"), %{"character" => %{}})
    assert has_element?(view, "img[alt='Selected character image']")
    assert Repo.get!(Character, character.id).primary_image_id == character.primary_image_id
    assert Revisions.latest_revision_number(:character, character.id) == 1
  end

  test "stale edits cannot attach an image or processing job", %{conn: conn, user: user} do
    {character, _} = character_with_image(user)
    {:ok, view, _} = live(conn, ~p"/character/#{character.slug}/edit")
    upload_image(view)

    assert {:ok, _} =
             Revisions.submit_edit(
               :character,
               character.id,
               %{description: "Newer edit"},
               "Updated",
               user
             )

    jobs_before = Repo.aggregate(Oban.Job, :count)
    render_submit(element(view, "#character-edit"), %{"character" => %{}})
    assert has_element?(view, "img[alt='Selected character image']")
    assert Repo.get!(Character, character.id).primary_image_id == character.primary_image_id
    assert Repo.aggregate(Oban.Job, :count) == jobs_before
    assert Repo.aggregate(CharacterImage, :count) == 1
  end

  test "permission and lock changes are checked again on save", %{conn: conn, user: user} do
    {character, _} = character_with_image(user)
    {:ok, view, _} = live(conn, ~p"/character/#{character.slug}/edit")
    upload_image(view)
    Repo.update_all(from(u in User, where: u.id == ^user.id), set: [can_edit: false])
    render_submit(element(view, "#character-edit"), %{"character" => %{}})
    assert Repo.get!(Character, character.id).primary_image_id == character.primary_image_id

    Repo.update_all(from(u in User, where: u.id == ^user.id), set: [can_edit: true])
    Repo.update_all(from(c in Character, where: c.id == ^character.id), set: [is_locked: true])
    render_submit(element(view, "#character-edit"), %{"character" => %{}})
    assert Repo.get!(Character, character.id).primary_image_id == character.primary_image_id
    assert Repo.aggregate(CharacterImage, :count) == 1
    assert Revisions.latest_revision_number(:character, character.id) == 1
  end

  test "client-supplied image IDs and uploader IDs are ignored", %{conn: conn, user: user} do
    {character, _} = character_with_image(user)
    other = UserFixtures.insert_user!()
    {foreign, _} = character_with_image(other)
    {:ok, view, _} = live(conn, ~p"/character/#{character.slug}/edit")

    render_submit(view, "save", %{
      "character" => %{
        "description" => "Only content should change",
        "primary_image_id" => foreign.primary_image_id,
        "uploaded_by" => other.id,
        "staged_image" => %{"id" => foreign.primary_image_id}
      }
    })

    assert Repo.get!(Character, character.id).primary_image_id == character.primary_image_id
    assert Repo.get!(CharacterImage, foreign.primary_image_id).character_id == foreign.id
  end

  test "unsupported formats and oversized files are rejected before saving", %{conn: conn} do
    for {name, bytes, type, error} <- [
          {"portrait.gif", "GIF89a", "image/gif", :not_accepted},
          {"portrait.png", :binary.copy(<<0>>, 10_000_001), "image/png", :too_large}
        ] do
      {:ok, view, _} = live(conn, ~p"/contribute/character")

      upload =
        file_input(view, "#character-edit", :character_image, [
          %{last_modified: 1, name: name, content: bytes, type: type}
        ])

      assert {:error, errors} = render_upload(upload, name)
      assert Enum.any?(errors, fn [_ref, reason] -> reason == error end)
      assert has_element?(view, "#character-image-editor [role=alert]")

      render_submit(element(view, "#character-edit"), %{
        "character" => %{"name" => "Invalid upload"}
      })

      refute Repo.get_by(Character, name: "Invalid upload")
    end

    refute_received :image_staged
  end

  test "failed appearance validation rolls back the attached image and its processing job", %{
    user: user
  } do
    image = %{id: UUIDv7.generate(), flags: %{is_image_nsfw: false, is_image_suggestive: false}}

    assert {:error, _} =
             Contributions.create(
               %{
                 name: "Rolled back portrait",
                 appearances: [
                   %{visual_novel_id: UUIDv7.generate(), role: "invalid", spoiler_level: 0}
                 ]
               },
               "Created",
               user,
               image
             )

    refute Repo.get_by(Character, name: "Rolled back portrait")
    refute Repo.get(CharacterImage, image.id)
    assert processing_jobs(image.id) == 0
    assert Repo.aggregate(CharacterHist, :count) == 0
  end

  defp character_with_image(user) do
    image = %{id: UUIDv7.generate(), flags: %{is_image_nsfw: false, is_image_suggestive: false}}

    {:ok, %{entity: character, change: change}} =
      Contributions.create(
        %{name: "Heroine #{System.unique_integer([:positive])}"},
        "Created",
        user,
        image
      )

    {character, change}
  end

  defp upload_image(view, bytes \\ png_binary()) do
    upload =
      file_input(view, "#character-edit", :character_image, [
        %{last_modified: 1, name: "portrait.png", content: bytes, type: "image/png"}
      ])

    render_upload(upload, "portrait.png")
  end

  defp processing_jobs(id) do
    Repo.aggregate(from(j in Oban.Job, where: fragment("?->>'id' = ?", j.args, ^id)), :count)
  end

  defp png_binary do
    Base.decode64!(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9WnQw1sAAAAASUVORK5CYII="
    )
  end
end
