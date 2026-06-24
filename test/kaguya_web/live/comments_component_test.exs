defmodule KaguyaWeb.CommentsComponentTest do
  use KaguyaWeb.ConnCase, async: false

  import Ecto.Query

  alias Kaguya.Lists
  alias Kaguya.Lists.{List, ListComment, ListCommentLike}
  alias Kaguya.Repo
  alias Kaguya.Reports.Report
  alias Kaguya.Test.UserFixtures
  alias KaguyaWeb.Comments.ListAdapter

  defmodule TestLive do
    use KaguyaWeb, :live_view

    alias Kaguya.Users
    alias KaguyaWeb.Comments.ListAdapter
    alias KaguyaWeb.CommentsComponent

    @impl true
    def mount(_params, session, socket) do
      current_user =
        case Map.get(session, "current_user_id") do
          nil -> nil
          user_id -> Users.get_user(user_id) |> elem(1)
        end

      {:ok,
       assign(socket,
         list_id: Map.fetch!(session, "list_id"),
         current_user: current_user
       )}
    end

    @impl true
    def render(assigns) do
      ~H"""
      <.live_component
        module={CommentsComponent}
        id="comments"
        adapter={ListAdapter}
        resource_id={@list_id}
        current_user={@current_user}
      />
      """
    end
  end

  test "creates top-level comments and replies through the list adapter", %{conn: conn} do
    user = UserFixtures.insert_user!(username: "commenter")
    list = insert_list!(user, "Commentable")

    {:ok, view, html} =
      live_isolated(conn, TestLive,
        session: %{"list_id" => list.id, "current_user_id" => user.id}
      )

    refute html =~ "No comments yet."

    html =
      render_submit(element(view, "#comments-top-form"), %{"content" => "Hello from LiveView"})

    assert html =~ "Hello from LiveView"

    # The composer pushes a reset event after success so the textarea clears
    # client-side via the MarkdownEditor hook. Mirrors what Next.js does after
    # a successful mutation.
    assert_push_event(view, "kaguya:markdown-editor-set", %{
      id: "comments-top-form",
      content: ""
    })

    parent = Repo.one!(from(c in ListComment, where: c.list_id == ^list.id))

    render_click(element(view, "#comment-#{parent.id}-reply"))

    html =
      render_submit(element(view, "#comment-#{parent.id}-reply-form"), %{
        "content" => "A nested reply"
      })

    reply = Repo.get_by!(ListComment, parent_comment_id: parent.id)
    assert reply.content == "A nested reply"
    assert html =~ "A nested reply"
  end

  test "failed comment submit leaves the textarea content alone (no clear event)", %{conn: conn} do
    # Unauthenticated session ⇒ adapter returns :unauthenticated.
    user = UserFixtures.insert_user!(username: "unauth_failtest")
    list = insert_list!(user, "FailComposer")

    {:ok, view, _html} =
      live_isolated(conn, TestLive, session: %{"list_id" => list.id, "current_user_id" => nil})

    html =
      render_submit(element(view, "#comments-top-form"), %{"content" => "Should not persist"})

    # No clear event — the textarea keeps the user's text so they can fix
    # the issue and retry without losing it.
    refute_push_event(view, "kaguya:markdown-editor-set", %{})
    assert html =~ "Sign in"
  end

  test "edits own comments and toggles likes", %{conn: conn} do
    author = UserFixtures.insert_user!(username: "author")
    liker = UserFixtures.insert_user!(username: "liker")
    list = insert_list!(author, "Editable")

    {:ok, comment} =
      Lists.create_list_comment(%{list_id: list.id, user_id: liker.id, content: "Original text"})

    {:ok, view, _html} =
      live_isolated(conn, TestLive,
        session: %{"list_id" => list.id, "current_user_id" => liker.id}
      )

    Phoenix.LiveView.send_update(view.pid, KaguyaWeb.CommentsComponent,
      id: "comments",
      editing_id: comment.id
    )

    render(view)

    html =
      render_submit(element(view, "#comment-#{comment.id}-edit-form"), %{
        "content" => "Edited text"
      })

    assert html =~ "Edited text"
    assert Repo.get!(ListComment, comment.id).is_edited

    html = render_click(element(view, "#comment-#{comment.id}-like"))
    assert html =~ "1"

    assert Repo.exists?(
             from(l in ListCommentLike,
               where: l.vn_list_comment_id == ^comment.id and l.user_id == ^liker.id
             )
           )

    render_click(element(view, "#comment-#{comment.id}-like"))

    refute Repo.exists?(
             from(l in ListCommentLike,
               where: l.vn_list_comment_id == ^comment.id and l.user_id == ^liker.id
             )
           )

    Phoenix.LiveView.send_update(view.pid, KaguyaWeb.CommentsComponent,
      id: "comments",
      pending_delete_id: comment.id
    )

    html = render(view)

    assert html =~ ~s(id="delete-comment-dialog-#{comment.id}")
    assert html =~ ~s(phx-hook="ModalDialog")
    assert html =~ ~s(data-cancel-event="cancel_delete_comment")
    assert html =~ ~s(data-modal-cancel)

    html = render_click(element(view, "#delete-comment-dialog-#{comment.id} button", "Cancel"))
    refute html =~ ~s(id="delete-comment-dialog-#{comment.id}")
    assert Repo.get!(ListComment, comment.id)
  end

  test "moderators can hide and unhide comments without losing the thread", %{conn: conn} do
    author = UserFixtures.insert_user!(username: "author")
    moderator = UserFixtures.insert_user!(username: "mod") |> promote_list_moderator()
    list = insert_list!(author, "Moderated")

    {:ok, comment} =
      Lists.create_list_comment(%{
        list_id: list.id,
        user_id: author.id,
        content: "Needs moderation"
      })

    {:ok, view, _html} =
      live_isolated(conn, TestLive,
        session: %{"list_id" => list.id, "current_user_id" => moderator.id}
      )

    assert {:ok, _count} = ListAdapter.hide(comment.id, moderator, %{})

    Phoenix.LiveView.send_update(view.pid, KaguyaWeb.CommentsComponent, id: "comments")

    html = render(view)

    assert html =~ "hidden"
    refute is_nil(Repo.get!(ListComment, comment.id).hidden_at)

    assert {:ok, _count} = ListAdapter.unhide(comment.id, moderator)

    assert is_nil(Repo.get!(ListComment, comment.id).hidden_at)
  end

  test "signed-in non-owners can report comments through the shared action menu", %{conn: conn} do
    author = UserFixtures.insert_user!(username: "author")
    reporter = UserFixtures.insert_user!(username: "reporter")
    list = insert_list!(author, "Reportable")

    {:ok, comment} =
      Lists.create_list_comment(%{
        list_id: list.id,
        user_id: author.id,
        content: "Needs review"
      })

    {:ok, view, html} =
      live_isolated(conn, TestLive,
        session: %{"list_id" => list.id, "current_user_id" => reporter.id}
      )

    assert html =~ "Report"

    Phoenix.LiveView.send_update(view.pid, KaguyaWeb.CommentsComponent,
      id: "comments",
      pending_report_id: comment.id
    )

    html = render(view)

    assert html =~ "Report Comment"
    assert html =~ ~s(id="report-comment-dialog-#{comment.id}")
    assert html =~ ~s(phx-hook="ModalDialog")
    assert html =~ ~s(data-cancel-event="cancel_report_comment")
    assert html =~ ~s(data-modal-initial-focus)

    html =
      render_submit(element(view, "#report-comment-form"), %{
        "category" => "spoilers",
        "reason" => "Unmarked ending spoiler",
        "message" => "Mentions the ending plainly."
      })

    assert html =~ "Report submitted successfully."

    report =
      Repo.get_by!(Report,
        reporter_id: reporter.id,
        entity_type: "list_comment",
        entity_id: comment.id
      )

    assert report.category == "spoilers"
    assert report.reason == "Unmarked ending spoiler"
    assert report.message == "Mentions the ending plainly."
  end

  test "list adapter renders safe comment markdown and never raw html", %{conn: conn} do
    user = UserFixtures.insert_user!(username: "safe")
    list = insert_list!(user, "Safe text")

    {:ok, _comment} =
      ListAdapter.create(list.id, user, %{
        content:
          "**bold** *italic* ~~gone~~ `code`\n[Kaguya](/lists) ||secret|| [bad](javascript:alert(1)) <script>alert(1)</script>\nhttps://example.test/path",
        parent_comment_id: nil
      })

    {:ok, _view, html} =
      live_isolated(conn, TestLive,
        session: %{"list_id" => list.id, "current_user_id" => user.id}
      )

    assert html =~ "<strong>"
    assert html =~ "bold"
    assert html =~ "<em>"
    assert html =~ "italic"
    assert html =~ "<del>"
    assert html =~ "gone"
    assert html =~ "<code"
    assert html =~ ~s(href="/lists")
    assert html =~ ~s(data-spoiler)
    assert html =~ "secret"
    assert html =~ "&lt;script&gt;alert(1)&lt;/script&gt;"
    assert html =~ ~s(href="https://example.test/path")
    refute html =~ ~s(href="javascript:alert)
    refute html =~ "<script>alert"
  end

  defp insert_list!(user, name) do
    %List{}
    |> List.changeset(%{
      user_id: user.id,
      name: "#{name} #{System.unique_integer([:positive])}",
      is_public: true
    })
    |> Repo.insert!()
  end

  defp promote_list_moderator(user) do
    Repo.update_all(from(u in Kaguya.Users.User, where: u.id == ^user.id), set: [mod_lists: true])
    Repo.get!(Kaguya.Users.User, user.id)
  end
end
