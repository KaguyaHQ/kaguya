defmodule KaguyaWeb.ProfileLive.Discussions do
  @moduledoc """
  `/@:username/discussions` — user discussion posts.

  Mirrors `../personal/legacy-next-app/src/components/profile/DiscussionsTab.tsx` and the
  shared `PostList` / `PostListItem` row components. LiveView reads the
  `Kaguya.Discussions` context directly and performs the same batched
  hydration needed by the profile discussion tab.
  """

  use KaguyaWeb.ProfileLive, tab: :discussions, title_suffix: "Discussions"

  import Ecto.Query

  alias Kaguya.Characters.Character
  alias Kaguya.Discussions
  alias Kaguya.Discussions.Comment
  alias Kaguya.Producers.Producer
  alias Kaguya.Repo
  alias Kaguya.Users.User
  alias Kaguya.VisualNovels.VisualNovel
  alias KaguyaWeb.Components.Discussions.PostList
  alias KaguyaWeb.Components.Profile.Placeholder
  alias KaguyaWeb.Discussions.Paths, as: DiscussionPaths

  @page_size 20

  @impl Phoenix.LiveView
  def handle_params(%{"username" => raw_username}, _uri, socket) do
    username = Data.parse_username(raw_username)
    viewer = socket.assigns[:current_user]

    case Data.load_header(username, viewer) do
      {:ok, profile} ->
        {posts, next_cursor, has_next} = load_posts(profile.id, viewer, nil)

        {:noreply,
         socket
         |> assign(:state, :ready)
         |> assign(:profile, profile)
         |> assign(:permissions, Data.viewer_permissions(viewer))
         |> assign(:page_title, Data.page_title(profile, "Discussions"))
         |> assign(:posts, posts)
         |> assign(:cursor, next_cursor)
         |> assign(:has_next, has_next)
         |> assign(:loading_more, false)}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> assign(:state, :not_found)
         |> assign(:page_title, "User not found · Kaguya")}
    end
  end

  @impl Phoenix.LiveView
  def render(%{state: :not_found} = assigns), do: Placeholder.not_found(assigns)
  def render(%{state: :loading} = assigns), do: Placeholder.loading(assigns)

  def render(assigns) do
    ~H"""
    <main class="min-h-screen bg-[rgb(var(--surface-base))] pb-10 text-[rgb(var(--foreground-primary))] lg:px-20 lg:pb-12">
      <Header.header profile={@profile} current_tab={@current_tab} permissions={@permissions} />

      <section class="mx-auto mt-8 flex w-full max-w-[988px] flex-1 flex-col max-lg:px-5 lg:mt-10">
        <div class="lg:grid lg:grid-cols-[1fr_270px] lg:gap-10">
          <div>
            <%= if @posts != [] do %>
              <div :if={@profile.viewer.is_mine} class="mb-4 flex justify-end lg:hidden">
                <.new_post_cta class="h-9 w-full text-xs sm:w-fit sm:text-sm" />
              </div>

              <PostList.post_list
                posts={@posts}
                has_more={@has_next}
                loading_more={@loading_more}
                show_removal_notice
              />
            <% else %>
              <.empty_discussions />
            <% end %>
          </div>

          <div class="max-lg:hidden">
            <.new_post_cta :if={@profile.viewer.is_mine} class="h-9 w-full text-sm" />
          </div>
        </div>
      </section>
    </main>
    """
  end

  @impl Phoenix.LiveView
  def handle_event("load_more_discussions", _params, %{assigns: %{cursor: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_event("load_more_discussions", _params, socket) do
    %{profile: profile, cursor: cursor} = socket.assigns
    viewer = socket.assigns[:current_user]

    socket = assign(socket, :loading_more, true)
    {items, next_cursor, has_next} = load_posts(profile.id, viewer, cursor)

    {:noreply,
     socket
     |> assign(:posts, socket.assigns.posts ++ items)
     |> assign(:cursor, next_cursor)
     |> assign(:has_next, has_next)
     |> assign(:loading_more, false)}
  end

  def handle_event("start_new_post", _params, socket) do
    {:noreply, put_flash(socket, :info, "The discussion composer is being migrated next.")}
  end

  def handle_event(event, params, socket) do
    super(event, params, socket)
  end

  attr :class, :any, default: nil

  defp new_post_cta(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="start_new_post"
      class={[
        "active:bg-button-background-neutral-inverse-pressed bg-button-background-neutral-inverse-default hover:bg-button-background-neutral-inverse-hover text-button-text-on-neutral-inverse inline-flex items-center justify-center gap-1.5 rounded-[4px] px-3 font-medium transition",
        @class
      ]}
    >
      <Lucide.plus class="size-[14px]" aria-hidden />
      <span>Start a new post</span>
    </button>
    """
  end

  defp empty_discussions(assigns) do
    ~H"""
    <div class="flex min-h-[180px] items-center justify-center rounded-lg border border-[rgb(var(--border-divider))]">
      <p class="text-sm text-[rgb(var(--foreground-secondary))]">No discussions yet.</p>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Loaders
  # ---------------------------------------------------------------------------

  defp load_posts(user_id, viewer, cursor) do
    opts =
      %{limit: @page_size, viewer_id: Data.viewer_id(viewer)}
      |> maybe_put(:cursor, cursor)

    case Discussions.list_posts_for_user(user_id, opts) do
      {:ok, %{items: items, next_cursor: next_cursor, has_next: has_next}} ->
        hydrated =
          items
          |> Repo.preload([:user, :last_comment_user])
          |> hydrate_posts()

        {hydrated, next_cursor, has_next}

      _ ->
        {[], nil, false}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp hydrate_posts([]), do: []

  defp hydrate_posts(posts) do
    recent_comment_users = load_recent_comment_users(posts)
    entity_maps = load_entities(posts)

    Enum.map(posts, fn post ->
      normalized =
        %{
          id: post.id,
          title: post.title,
          slug: post.slug,
          short_id: post.short_id,
          content: post.content,
          comments_count: post.comments_count || 0,
          likes_count: post.likes_count || 0,
          last_comment_at: post.last_comment_at,
          inserted_at: post.inserted_at,
          is_pinned: post.is_pinned,
          is_locked: post.is_locked,
          hidden_at: post.hidden_at,
          deleted_at: post.deleted_at,
          deleted_by_type: post.deleted_by_type,
          category_type: post.category_type,
          entity_id: post.entity_id,
          user: Data.normalize_user(loaded_user(post.user)),
          last_comment_user: maybe_normalize_user(post.last_comment_user),
          recent_comment_users:
            post.id
            |> then(&Map.get(recent_comment_users, &1, []))
            |> Enum.map(&Data.normalize_user/1)
        }
        |> Map.merge(entity_for_post(post, entity_maps))

      normalized
      |> Map.put(:href, DiscussionPaths.post_url(normalized))
      |> Map.put(:entity_tag, DiscussionPaths.entity_tag(normalized))
    end)
  end

  defp load_recent_comment_users(posts) do
    post_ids = Enum.map(posts, & &1.id)

    if post_ids == [] do
      %{}
    else
      from(c in Comment,
        join: u in User,
        on: u.id == c.user_id,
        where: c.post_id in ^post_ids and is_nil(c.hidden_at) and is_nil(c.deleted_at),
        order_by: [desc: c.inserted_at],
        select: {c.post_id, u}
      )
      |> Repo.all()
      |> Enum.reduce(%{}, fn {post_id, user}, acc ->
        Map.update(acc, post_id, [user], fn users ->
          cond do
            Enum.any?(users, &(&1.id == user.id)) -> users
            length(users) >= 3 -> users
            true -> users ++ [user]
          end
        end)
      end)
    end
  end

  defp load_entities(posts) do
    %{
      visual_novel: load_entity(posts, :visual_novel, VisualNovel),
      producer: load_entity(posts, :producer, Producer),
      character: load_entity(posts, :character, Character),
      user: load_entity(posts, :user, User)
    }
  end

  defp load_entity(posts, category, schema) do
    ids =
      posts
      |> Enum.filter(&(&1.category_type == category and is_binary(&1.entity_id)))
      |> Enum.map(& &1.entity_id)
      |> Enum.uniq()

    if ids == [] do
      %{}
    else
      from(e in schema, where: e.id in ^ids)
      |> Repo.all()
      |> Map.new(&{&1.id, normalize_entity(&1)})
    end
  end

  defp entity_for_post(%{category_type: :visual_novel, entity_id: id}, %{visual_novel: map}),
    do: %{visual_novel: Map.get(map, id)}

  defp entity_for_post(%{category_type: :producer, entity_id: id}, %{producer: map}),
    do: %{producer: Map.get(map, id)}

  defp entity_for_post(%{category_type: :character, entity_id: id}, %{character: map}),
    do: %{character: Map.get(map, id)}

  defp entity_for_post(%{category_type: :user, entity_id: id}, %{user: map}),
    do: %{target_user: Map.get(map, id)}

  defp entity_for_post(_post, _maps), do: %{}

  defp normalize_entity(%VisualNovel{} = vn), do: %{id: vn.id, title: vn.title, slug: vn.slug}

  defp normalize_entity(%Producer{} = producer),
    do: %{id: producer.id, name: producer.name, slug: producer.slug}

  defp normalize_entity(%Character{} = character),
    do: %{id: character.id, name: character.name, slug: character.slug}

  defp normalize_entity(%User{} = user), do: Data.normalize_user(user)

  defp loaded_user(%Ecto.Association.NotLoaded{}), do: nil
  defp loaded_user(user), do: user

  defp maybe_normalize_user(%Ecto.Association.NotLoaded{}), do: nil
  defp maybe_normalize_user(nil), do: nil
  defp maybe_normalize_user(user), do: Data.normalize_user(user)
end
