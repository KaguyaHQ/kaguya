defmodule KaguyaWeb.DeveloperLive.ShowTest do
  use KaguyaWeb.ConnCase, async: false

  alias Kaguya.Discussions
  alias Kaguya.Producers.Producer
  alias Kaguya.Repo
  alias Kaguya.Users.User
  alias KaguyaWeb.UserAuth

  # Regression test for the duplicate-ID crash that originally motivated this
  # refactor: a moderator navigating to /developer/:slug hit a 10-second 500
  # because EntityModActions was rendered twice (mobile + desktop layout
  # forks). The mod-as-viewer render path now has zero moderation widgets —
  # mod actions live on the Edit form — so the page renders cleanly for both
  # mods and non-mods. This test guards both invariants from regressing.

  test "renders without crashing for a moderator viewing the page", %{conn: conn} do
    producer = insert_producer!("Black Tabby Games")
    mod = insert_mod!()

    {:ok, _view, html} =
      conn
      |> log_in(mod)
      |> live(~p"/developer/#{producer.slug}")

    assert html =~ producer.name
    # The mod-actions chip + dropdown should be absent from the read surface
    # — moderation moved to the Edit form.
    refute html =~ "producer-mod-actions"
    refute html =~ "Mod actions"
  end

  test "renders without crashing for an anonymous viewer", %{conn: conn} do
    producer = insert_producer!("Anon-View Studio")

    {:ok, _view, html} = live(conn, ~p"/developer/#{producer.slug}")

    assert html =~ producer.name
    refute html =~ "producer-mod-actions"
  end

  test "renders developer-scoped discussions", %{conn: conn} do
    producer = insert_producer!("Discussion Studio")
    author = insert_user!()

    assert {:ok, post} =
             Discussions.create_post(author.id, %{
               title: "A developer branch discussion",
               content:
                 "Discussion content long enough for the developer scoped discussion fixture.",
               category_type: :producer,
               entity_id: producer.id
             })

    {:ok, view, _html} = live(conn, ~p"/developer/#{producer.slug}")

    assert has_element?(view, "#developer-discussion-#{post.id}")
    html = render(view)
    assert html =~ "A developer branch discussion"
    assert html =~ author.display_name
    assert html =~ ~s(href="/developer/#{producer.slug}/discussions/#{post.short_id}")
  end

  defp insert_producer!(name) do
    %Producer{}
    |> Producer.changeset(%{name: name})
    |> Repo.insert!()
  end

  defp insert_user! do
    suffix = System.unique_integer([:positive])

    %User{}
    |> User.create_changeset(%{
      id: Ecto.UUID.generate(),
      username: "developer_show_user_#{suffix}",
      display_name: "Developer Show Viewer #{suffix}",
      email: "developer-show-#{suffix}@example.com"
    })
    |> Repo.insert!()
  end

  defp insert_mod! do
    insert_user!()
    |> Ecto.Changeset.change(%{mod_db: true, role: :moderator})
    |> Repo.update!()
  end

  defp log_in(conn, %User{} = user) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> UserAuth.log_in_user(user)
  end
end
