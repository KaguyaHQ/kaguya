defmodule KaguyaWeb.ProfileLive.Activity do
  @moduledoc """
  `/@:username/activity` — user activity feed.

  Mirrors `../personal/legacy-next-app/src/app/(main)/(maxWidthWrapper)/users/[username]/(tabs)/activity/page.tsx`
  and the React components under `../personal/legacy-next-app/src/components/profile/activity/`:

    * Left column (lg:w-[71%]): paginated activity feed. Each row dispatches
      to a verb-specific layout via
      `KaguyaWeb.Components.Profile.Activity.activity_item/1`.
    * Right rail (lg:w-[27%], hidden on mobile): the 25-avatar "Following"
      grid, or a "Members worth following" empty-state when the owner
      follows nobody.

  Pagination is cursor-based. Production auto-loads the first two pages, then
  switches to the manual "Load older activity" button; this LiveView uses
  `phx-viewport-bottom` until 40 rows are loaded, then renders the button.
  """

  use KaguyaWeb.ProfileLive, tab: :activity, title_suffix: "Activity"

  import Ecto.Query, only: [from: 2]
  import KaguyaWeb.SharedComponents.LoadMore

  alias Kaguya.{Activities, Repo, Reviews, Social, VisualNovels}
  alias Kaguya.Lists.ListItem
  alias Kaguya.Reviews.Rating
  alias KaguyaWeb.Components.Profile.Placeholder
  alias KaguyaWeb.Components.Profile.Activity, as: ActivityComponents
  alias KaguyaWeb.ProfileLive.Data

  @page_size 20
  @auto_load_until @page_size * 2
  @sidebar_avatar_count 25

  @impl Phoenix.LiveView
  def render(%{state: :not_found} = assigns), do: Placeholder.not_found(assigns)
  def render(%{state: :loading} = assigns), do: Placeholder.loading(assigns)

  def render(assigns) do
    ~H"""
    <main class="min-h-screen bg-[rgb(var(--surface-base))] pb-10 text-[rgb(var(--foreground-primary))] lg:px-20 lg:pb-12">
      <Header.header profile={@profile} current_tab={@current_tab} permissions={@permissions} />

      <div class="mx-auto mt-8 w-full max-w-[988px] lg:mt-10">
        <div class="lg:flex lg:gap-16">
          <div class="min-w-0 lg:w-[71%]">
            <%= cond do %>
              <% @activities == [] -> %>
                <ActivityComponents.empty_feed />
              <% true -> %>
                <div>
                  <ActivityComponents.activity_item
                    :for={item <- @activities}
                    item={item}
                    username={@profile.username}
                    display_name={@profile.display_name}
                  />
                </div>

                <%= cond do %>
                  <% @has_next and @loaded_count < @auto_load_until -> %>
                    <div
                      id="activity-auto-loader"
                      phx-hook="ActivityAutoLoad"
                      data-loading-more={to_string(@loading_more)}
                      aria-live="polite"
                      class="flex items-center justify-center pt-8 pb-0 text-sm text-[rgb(var(--foreground-secondary))] lg:pb-8"
                    >
                      Loading more activity
                    </div>
                  <% @has_next -> %>
                    <div class="flex w-full items-center justify-center pt-8 pb-0 lg:pb-8">
                      <.load_more
                        phx-click="load_more_activity"
                        disabled={@loading_more}
                        label="Load older activity"
                        loading_label="Loading…"
                        class="px-6"
                      />
                    </div>
                  <% true -> %>
                    <ActivityComponents.end_of_feed />
                <% end %>
            <% end %>
          </div>

          <aside class="hidden lg:block lg:w-[27%]">
            <ActivityComponents.sidebar
              username={@profile.username}
              following_users={@following_users}
              following_count={@following_count}
              discover_users={@discover_users}
            />
          </aside>
        </div>
      </div>
    </main>
    """
  end

  @impl Phoenix.LiveView
  def handle_params(%{"username" => raw_username}, _uri, socket) do
    username = Data.parse_username(raw_username)
    viewer = socket.assigns[:current_user]

    case Data.load_header(username, viewer) do
      {:ok, profile} ->
        {activities, next_cursor, has_next} = load_feed(profile.id, viewer, nil)
        {following_users, following_count} = load_following(profile)

        {:noreply,
         socket
         |> assign(:state, :ready)
         |> assign(:profile, profile)
         |> assign(:permissions, Data.viewer_permissions(viewer))
         |> assign(:page_title, Data.page_title(profile, "Activity"))
         |> assign(KaguyaWeb.SEO.noindex())
         |> assign(:activities, activities)
         |> assign(:auto_load_until, @auto_load_until)
         |> assign(:loaded_count, length(activities))
         |> assign(:cursor, next_cursor)
         |> assign(:has_next, has_next)
         |> assign(:loading_more, false)
         |> assign(:following_users, following_users)
         |> assign(:following_count, following_count)
         |> assign(:discover_users, [])}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> assign(:state, :not_found)
         |> assign(:page_title, "User not found · Kaguya")}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("load_more_activity", _params, %{assigns: %{cursor: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_event("load_more_activity", _params, socket) do
    %{profile: profile, cursor: cursor} = socket.assigns
    viewer = socket.assigns[:current_user]

    socket = assign(socket, :loading_more, true)
    {items, next_cursor, has_next} = load_feed(profile.id, viewer, cursor)

    {:noreply,
     socket
     |> assign(:activities, socket.assigns.activities ++ items)
     |> assign(:loaded_count, length(socket.assigns.activities) + length(items))
     |> assign(:cursor, next_cursor)
     |> assign(:has_next, has_next)
     |> assign(:loading_more, false)}
  end

  def handle_event("toggle_review_like", %{"review-id" => review_id}, socket) do
    case socket.assigns[:current_user] do
      %{id: user_id} ->
        toggle_like_optimistic(socket, review_id, user_id)

      _ ->
        {:noreply, Phoenix.LiveView.put_flash(socket, :error, "Sign in to like reviews.")}
    end
  end

  # Delegate other events to the shared profile event handlers.
  def handle_event(event, params, socket) when event in ["toggle_follow", "open_mod_panel"] do
    super(event, params, socket)
  end

  defp toggle_like_optimistic(socket, review_id, user_id) do
    activities = socket.assigns.activities

    target_item =
      Enum.find(activities, fn item ->
        (item.action == :reviewed and item.review) &&
          to_string(item.review.id) == to_string(review_id)
      end)

    cond do
      is_nil(target_item) ->
        {:noreply, socket}

      target_item.review.liked_by_me ->
        do_toggle_like(
          socket,
          target_item.review.id,
          &Reviews.unlike_review(&1, user_id),
          :unlike
        )

      true ->
        do_toggle_like(socket, target_item.review.id, &Reviews.like_review(&1, user_id), :like)
    end
  end

  defp do_toggle_like(socket, review_id, mutation, direction) do
    delta = if direction == :like, do: 1, else: -1
    liked? = direction == :like
    optimistic = update_review_in_activities(socket.assigns.activities, review_id, delta, liked?)
    socket = assign(socket, :activities, optimistic)

    case mutation.(review_id) do
      {:ok, _} ->
        {:noreply, socket}

      {:error, reason} ->
        rolled_back = update_review_in_activities(optimistic, review_id, -delta, not liked?)

        {:noreply,
         socket
         |> assign(:activities, rolled_back)
         |> Phoenix.LiveView.put_flash(:error, like_error_message(reason))}
    end
  end

  defp update_review_in_activities(activities, review_id, delta, liked?) do
    Enum.map(activities, fn item ->
      if (item.action == :reviewed and item.review) &&
           to_string(item.review.id) == to_string(review_id) do
        review = item.review

        updated = %{
          review
          | likes_count: max(0, (review.likes_count || 0) + delta),
            liked_by_me: liked?
        }

        %{item | review: updated}
      else
        item
      end
    end)
  end

  defp like_error_message(reason) when is_binary(reason), do: reason
  defp like_error_message(_), do: "Could not update this like."

  # ---------------------------------------------------------------------------
  # Loaders
  # ---------------------------------------------------------------------------

  defp load_feed(user_id, viewer, cursor) do
    viewer_id = viewer && viewer.id

    opts =
      [
        limit: @page_size,
        viewer_id: viewer_id,
        screenshot_prefs: screenshot_prefs_for(viewer)
      ]
      |> maybe_put(:cursor, cursor)

    case Activities.list_activities_for_user(user_id, opts) do
      {:ok, %{items: items, next_cursor: next_cursor, has_next: has_next}} ->
        loaded =
          %{items: items}
          |> Activities.preload_associations()
          |> Map.fetch!(:items)
          |> normalize_card_associations(viewer_id)

        {loaded, next_cursor, has_next}

      _ ->
        {[], nil, false}
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp screenshot_prefs_for(%{} = user) do
    %{
      show_nsfw: Map.get(user, :show_nsfw_screenshots, false),
      show_brutal: Map.get(user, :show_brutal_screenshots, false)
    }
  end

  defp screenshot_prefs_for(_), do: %{show_nsfw: false, show_brutal: false}

  defp normalize_card_associations(items, viewer_id) do
    reviews_loaded =
      items
      |> Enum.filter(&(&1.action == :reviewed and not is_nil(&1.review)))
      |> Enum.map(& &1.review)
      |> Repo.preload([:user, :visual_novel])

    rating_lookup = batch_ratings_for_reviews(reviews_loaded)
    liked_ids = liked_review_id_set(viewer_id, reviews_loaded)

    reviews_by_id =
      Map.new(reviews_loaded, fn review ->
        {review.id, normalize_review(review, rating_lookup, liked_ids)}
      end)

    list_covers_by_id =
      items
      |> Enum.filter(&(&1.action == :created_list and not is_nil(&1.list)))
      |> Enum.map(& &1.list.id)
      |> load_list_covers()

    Enum.map(items, fn item ->
      case item.action do
        :reviewed ->
          %{item | review: Map.get(reviews_by_id, item.entity_id)}

        :created_list ->
          %{
            item
            | list: normalize_list(item.list, Map.get(list_covers_by_id, item.entity_id, []))
          }

        _ ->
          item
      end
    end)
  end

  defp normalize_review(review, rating_lookup, liked_ids) do
    user = review.user
    vn = review.visual_novel
    rating_value = Map.get(rating_lookup, {review.user_id, review.visual_novel_id})

    %{
      id: review.id,
      content: review.content,
      rating: rating_value,
      likes_count: review.likes_count || 0,
      comments_count: review.comments_count || 0,
      liked_by_me: MapSet.member?(liked_ids, to_string(review.id)),
      is_spoiler: review.is_spoiler,
      is_edited: review.is_edited,
      inserted_at: review.inserted_at,
      user: user && %{username: user.username, display_name: user.display_name || user.username},
      visual_novel: normalize_vn(vn)
    }
  end

  defp batch_ratings_for_reviews([]), do: %{}

  defp batch_ratings_for_reviews(reviews) do
    pairs = reviews |> Enum.map(&{&1.user_id, &1.visual_novel_id}) |> Enum.uniq()
    user_ids = pairs |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
    vn_ids = pairs |> Enum.map(&elem(&1, 1)) |> Enum.uniq()

    from(rat in Rating,
      where: rat.user_id in ^user_ids and rat.visual_novel_id in ^vn_ids,
      select: {{rat.user_id, rat.visual_novel_id}, rat.rating}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp liked_review_id_set(nil, _reviews), do: MapSet.new()
  defp liked_review_id_set(_viewer, []), do: MapSet.new()

  defp liked_review_id_set(viewer_id, reviews) do
    reviews
    |> Enum.map(& &1.id)
    |> then(&Reviews.liked_review_ids_in(viewer_id, &1))
    |> MapSet.new(&to_string/1)
  end

  defp normalize_list(nil, _covers), do: nil

  defp normalize_list(list, covers) do
    user = list.user

    %{
      id: list.id,
      name: list.name,
      slug: list.slug,
      vns_count: list.vns_count || 0,
      likes_count: list.likes_count || 0,
      inserted_at: list.inserted_at,
      last_activity_at: list.last_activity_at,
      user: user && %{username: user.username, display_name: user.display_name || user.username},
      username: user && user.username,
      cover_urls: covers
    }
  end

  defp load_list_covers([]), do: %{}

  defp load_list_covers(list_ids) do
    rows =
      from(li in ListItem,
        join: vn in assoc(li, :visual_novel),
        where: li.list_id in ^Enum.uniq(list_ids),
        order_by: [asc: li.list_id, asc: li.position],
        select: {li.list_id, vn}
      )
      |> Repo.all()

    rows
    |> Enum.group_by(fn {list_id, _vn} -> list_id end, fn {_list_id, vn} -> normalize_vn(vn) end)
    |> Map.new(fn {list_id, vns} -> {list_id, Enum.take(vns, 11)} end)
  end

  defp normalize_vn(nil), do: nil

  defp normalize_vn(vn) do
    %{
      id: vn.id,
      slug: vn.slug,
      title: vn.title,
      has_ero: vn.has_ero,
      images: VisualNovels.build_image_urls(vn),
      is_image_nsfw: Map.get(vn, :is_image_nsfw, false),
      is_image_suggestive: Map.get(vn, :is_image_suggestive, false)
    }
  end

  defp load_following(profile) do
    case Social.list_following_by_user_id(profile.id, nil, @sidebar_avatar_count) do
      {:ok, %{items: items}} ->
        users =
          items
          |> Enum.reject(&is_nil/1)
          |> Enum.map(&Data.normalize_user/1)

        {users, profile.counts.following || 0}

      _ ->
        {[], profile.counts.following || 0}
    end
  end
end
