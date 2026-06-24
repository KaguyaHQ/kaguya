defmodule KaguyaWeb.DeveloperLive.EditTest do
  use KaguyaWeb.ConnCase, async: false

  import Ecto.Query

  alias Kaguya.Producers.{Producer, ProducerExternalLink}
  alias Kaguya.Repo
  alias Kaguya.Revisions.Change
  alias Kaguya.Users.User
  alias KaguyaWeb.UserAuth

  test "renders auth prompt for anonymous viewers", %{conn: conn} do
    producer = insert_producer!("Anon Dev")

    {:ok, _view, html} = live(conn, ~p"/developer/#{producer.slug}/edit")

    assert html =~ "Sign in to edit this developer."
  end

  test "submits producer edits and normalizes full social URLs", %{conn: conn} do
    producer = insert_producer!("Patchouli Works")
    user = insert_user!()

    {:ok, view, _html} =
      conn
      |> log_in(user)
      |> live(~p"/developer/#{producer.slug}/edit")

    expected_path = "/developer/#{producer.slug}"

    assert {:error, {:live_redirect, %{to: ^expected_path}}} =
             view
             |> element("form#developer-edit-form")
             |> render_submit(%{
               "developer" => %{
                 "name" => "Patchouli Works Studio",
                 "description" => "Updated profile",
                 "producer_type" => "developer",
                 "language" => "ja",
                 "summary" => "Updated core fields",
                 "external_links" => %{
                   "0" => %{"site" => "twitter", "value" => "https://x.com/patchouliworks"}
                 }
               }
             })

    updated = Repo.get!(Producer, producer.id)
    assert updated.name == "Patchouli Works Studio"
    assert updated.description == "Updated profile"
    assert updated.producer_type == "developer"
    assert updated.language == "ja"

    links =
      Repo.all(
        from l in ProducerExternalLink,
          where: l.producer_id == ^producer.id,
          select: {l.site, l.value}
      )

    assert links == [{"twitter", "patchouliworks"}]
  end

  test "moderator hide via Edit form sets hidden_at and records :hide action", %{conn: conn} do
    producer = insert_producer!("Foggy Studio")
    mod = insert_mod!()

    {:ok, view, _html} =
      conn
      |> log_in(mod)
      |> live(~p"/developer/#{producer.slug}/edit")

    expected_path = "/developer/#{producer.slug}"

    assert {:error, {:live_redirect, %{to: ^expected_path}}} =
             view
             |> element("form#developer-edit-form")
             |> render_submit(%{
               "developer" => %{
                 "name" => producer.name,
                 "description" => "",
                 "producer_type" => "",
                 "language" => "",
                 "summary" => "Spam entry",
                 "is_hidden" => "true"
               }
             })

    updated = Repo.get!(Producer, producer.id)
    refute is_nil(updated.hidden_at)
    refute updated.is_locked

    change = latest_change!(producer.id)
    assert change.action == :hide
    assert change.summary == "Spam entry"
  end

  test "non-mod cannot escalate via forged is_locked param", %{conn: conn} do
    producer = insert_producer!("Locked-target Studio")
    user = insert_user!()

    {:ok, view, _html} =
      conn
      |> log_in(user)
      |> live(~p"/developer/#{producer.slug}/edit")

    expected_path = "/developer/#{producer.slug}"

    # User has no `mod_db` and no admin/moderator role. They submit a normal
    # edit + a forged is_locked=true. The mod-only fieldset isn't rendered for
    # them, but a crafted POST is the actual attack we defend against.
    assert {:error, {:live_redirect, %{to: ^expected_path}}} =
             view
             |> element("form#developer-edit-form")
             |> render_submit(%{
               "developer" => %{
                 "name" => "Renamed",
                 "description" => "",
                 "producer_type" => "",
                 "language" => "",
                 "summary" => "Just a rename",
                 "is_locked" => "true",
                 "is_hidden" => "true"
               }
             })

    updated = Repo.get!(Producer, producer.id)
    refute updated.is_locked
    assert is_nil(updated.hidden_at)
    assert updated.name == "Renamed"

    change = latest_change!(producer.id)
    assert change.action == :edit
  end

  test "moderator can reach the Edit form on a locked entry", %{conn: conn} do
    producer = insert_locked_producer!("Vault Studio")
    mod = insert_mod!()

    {:ok, _view, html} =
      conn
      |> log_in(mod)
      |> live(~p"/developer/#{producer.slug}/edit")

    # If the lock-gate still applied to mods we'd see the "is locked" message;
    # instead the editing form (and the Moderation fieldset) renders.
    refute html =~ "is locked and cannot be edited"
    assert html =~ "developer-edit-form"
    assert html =~ "Moderation"
  end

  test "non-mod still gets the locked redirect on a locked entry", %{conn: conn} do
    producer = insert_locked_producer!("Sealed Studio")
    user = insert_user!()

    {:ok, _view, html} =
      conn
      |> log_in(user)
      |> live(~p"/developer/#{producer.slug}/edit")

    assert html =~ "is locked and cannot be edited"
    refute html =~ "developer-edit-form"
  end

  test "renders auth prompt for anonymous viewers on the create page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/contribute/developer")

    assert html =~ "Sign in to add a developer."
  end

  test "blocks creating for users without editing permission", %{conn: conn} do
    user = insert_restricted_user!()

    {:ok, _view, html} =
      conn
      |> log_in(user)
      |> live(~p"/contribute/developer")

    assert html =~ "You do not have permission to add a developer."
  end

  test "creates a developer from the create form", %{conn: conn} do
    user = insert_user!()

    {:ok, view, _html} =
      conn
      |> log_in(user)
      |> live(~p"/contribute/developer")

    assert {:error, {:live_redirect, %{to: "/developer/created-test-studio"}}} =
             view
             |> element("form#developer-edit-form")
             |> render_submit(%{
               "developer" => %{
                 "name" => "Created Test Studio",
                 "description" => "A brand new studio",
                 "producer_type" => "developer",
                 "language" => "ja",
                 "summary" => "",
                 "external_links" => %{
                   "0" => %{"site" => "twitter", "value" => "https://x.com/createdstudio"}
                 }
               }
             })

    created = Repo.get_by!(Producer, slug: "created-test-studio")
    assert created.name == "Created Test Studio"
    assert created.description == "A brand new studio"
    assert created.producer_type == "developer"
    assert created.language == "ja"

    links =
      Repo.all(
        from l in ProducerExternalLink,
          where: l.producer_id == ^created.id,
          select: {l.site, l.value}
      )

    assert links == [{"twitter", "createdstudio"}]
  end

  defp insert_producer!(name) do
    %Producer{}
    |> Producer.changeset(%{name: name})
    |> Repo.insert!()
  end

  defp insert_locked_producer!(name) do
    insert_producer!(name)
    |> Ecto.Changeset.change(%{is_locked: true})
    |> Repo.update!()
  end

  defp insert_user! do
    suffix = System.unique_integer([:positive])

    %User{}
    |> User.create_changeset(%{
      id: Ecto.UUID.generate(),
      username: "developer_edit_user_#{suffix}",
      display_name: "Developer Editor #{suffix}",
      email: "developer-edit-#{suffix}@example.com"
    })
    |> Repo.insert!()
  end

  defp insert_mod! do
    insert_user!()
    |> Ecto.Changeset.change(%{mod_db: true, role: :moderator})
    |> Repo.update!()
  end

  defp insert_restricted_user! do
    insert_user!()
    |> Ecto.Changeset.change(%{can_edit: false})
    |> Repo.update!()
  end

  # ensure_initial_revision/3 synthesizes a r1 `:create` row before the user's
  # edit lands when none exists, so a freshly-inserted producer accumulates
  # two `changes` rows after one user save. Look at the highest revision.
  defp latest_change!(entity_id) do
    Repo.one!(
      from c in Change,
        where: c.entity_id == ^entity_id,
        order_by: [desc: c.revision_number],
        limit: 1
    )
  end

  defp log_in(conn, %User{} = user) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> UserAuth.log_in_user(user)
  end
end
