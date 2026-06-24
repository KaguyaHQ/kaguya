defmodule KaguyaWeb.HomeLive.Index do
  use KaguyaWeb, :live_view

  alias Kaguya.Discussions
  alias Kaguya.Reviews
  alias KaguyaWeb.Home.FeedComponents
  alias KaguyaWeb.HomeLive.Data
  alias KaguyaWeb.HomeLive.Landing

  @signed_in_title "Home · Kaguya"
  @signed_in_description "Recent visual novel reviews, lists, discussions, and community activity on Kaguya."

  # Bounded sidebar starts with one page (BOUNDED_LIMIT = 20 entries) and
  # tops up at most one extra page (BOUNDED_TOP_UP_LIMIT = 30) when the
  # rendered rail is shorter than the viewport.
  @bounded_top_up_limit 30
  @bounded_max_pages 2

  @impl true
  def mount(_params, _session, %{assigns: %{current_user: nil}} = socket) do
    {:ok, Landing.assign_landing(socket)}
  end

  def mount(_params, _session, %{assigns: %{current_user: current_user}} = socket) do
    if blank?(Map.get(current_user, :username)) do
      {:ok, redirect(socket, to: ~p"/signup?action=account_setup")}
    else
      {:ok, load_home(socket)}
    end
  end

  @impl true
  def render(%{current_user: nil} = assigns) do
    ~H"""
    <Landing.landing_page
      hero_image={@hero_image}
      covers={@covers}
      stats={@stats}
      showcases={@showcases}
    />
    """
  end

  def render(assigns) do
    ~H"""
    <FeedComponents.home
      display_name={Map.get(@current_user, :display_name) || ""}
      feed={@feed}
      activity={@activity}
      activity_type={@activity_type}
      has_follows?={@has_follows?}
      mobile_tab={@mobile_tab}
      activity_can_top_up={can_top_up?(@activity, @activity_pages_loaded, @activity_top_up_failed)}
    />
    """
  end

  @impl true
  def handle_event("set_mobile_home_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :mobile_tab, mobile_tab(tab))}
  end

  def handle_event("set_activity_type", %{"type" => type}, socket) do
    activity_type = activity_type(type)

    case Data.load_activity(
           socket.assigns.current_user,
           activity_type,
           nil,
           Data.activity_limit()
         ) do
      {:ok, activity} ->
        {:noreply,
         assign(socket,
           activity: activity,
           activity_type: activity_type,
           activity_pages_loaded: 1,
           activity_top_up_failed: false
         )}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not load activity.")}
    end
  end

  # Bounded sidebar backstop: same-user compaction can shrink a single
  # 20-entry page to a handful of rows, leaving the rail visually tiny.
  # The JS hook (`HomeActivityTopUp`) measures the rendered height and
  # asks for one more page when there's clearly room — guarded by
  # @bounded_max_pages so a feed of pure compaction can't keep paging
  # forever.
  def handle_event("bounded_top_up", _params, socket) do
    activity = socket.assigns.activity
    pages = socket.assigns.activity_pages_loaded

    cond do
      pages >= @bounded_max_pages ->
        {:noreply, socket}

      not activity.has_next or is_nil(activity.next_cursor) ->
        {:noreply, socket}

      true ->
        case Data.load_activity(
               socket.assigns.current_user,
               socket.assigns.activity_type,
               activity.next_cursor,
               @bounded_top_up_limit
             ) do
          {:ok, page} ->
            merged = stitch_adjacent_entries(activity.entries, page.entries)

            updated =
              activity
              |> Map.put(:entries, merged)
              |> Map.put(:next_cursor, page.next_cursor)
              |> Map.put(:has_next, page.has_next)

            {:noreply,
             socket
             |> assign(:activity, updated)
             |> assign(:activity_pages_loaded, pages + 1)}

          {:error, _reason} ->
            {:noreply, assign(socket, :activity_top_up_failed, true)}
        end
    end
  end

  def handle_event("load_more_feed", _params, socket) do
    case socket.assigns.feed do
      %{has_next: true, next_cursor: cursor} when not is_nil(cursor) ->
        case Data.load_feed(socket.assigns.current_user, cursor, Data.feed_limit()) do
          {:ok, page} ->
            feed =
              socket.assigns.feed
              |> Map.put(:items, socket.assigns.feed.items ++ page.items)
              |> Map.put(:next_cursor, page.next_cursor)
              |> Map.put(:has_next, page.has_next)

            {:noreply, assign(socket, :feed, feed)}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, "Could not load more feed items.")}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("load_more_activity", _params, socket) do
    case socket.assigns.activity do
      %{has_next: true, next_cursor: cursor} when not is_nil(cursor) ->
        case Data.load_activity(
               socket.assigns.current_user,
               socket.assigns.activity_type,
               cursor,
               Data.activity_limit()
             ) do
          {:ok, page} ->
            merged_entries =
              stitch_adjacent_entries(socket.assigns.activity.entries, page.entries)

            activity =
              socket.assigns.activity
              |> Map.put(:entries, merged_entries)
              |> Map.put(:next_cursor, page.next_cursor)
              |> Map.put(:has_next, page.has_next)

            {:noreply, assign(socket, :activity, activity)}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, "Could not load more activity.")}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_feed_review_like", %{"review-id" => review_id}, socket) do
    with %{id: user_id} <- socket.assigns.current_user,
         liked? <- feed_review_liked?(socket.assigns.feed.items, review_id),
         {:ok, _} <- toggle_review_like(liked?, review_id, user_id) do
      {:noreply, update(socket, :feed, &update_review_like(&1, review_id, !liked?))}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not update this like.")}
    end
  end

  def handle_event("toggle_feed_post_like", %{"id" => post_id}, socket) do
    with %{id: user_id} <- socket.assigns.current_user,
         liked? <- feed_post_liked?(socket.assigns.feed.items, post_id),
         {:ok, _} <- toggle_post_like(liked?, post_id, user_id) do
      {:noreply, update(socket, :feed, &update_post_like(&1, post_id, !liked?))}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not update this like.")}
    end
  end

  defp load_home(socket) do
    case Data.load_initial_page(socket.assigns.current_user) do
      {:ok, payload} ->
        socket
        |> assign(:page_title, @signed_in_title)
        |> assign(:meta_description, @signed_in_description)
        |> assign(:canonical_url, "https://kaguya.io")
        |> assign(:nav_transparent, false)
        |> assign(:activity_pages_loaded, 1)
        |> assign(:activity_top_up_failed, false)
        |> assign(payload)

      {:error, _reason} ->
        socket
        |> assign(:page_title, @signed_in_title)
        |> assign(:meta_description, @signed_in_description)
        |> assign(:nav_transparent, false)
        |> assign(:feed, %{items: [], next_cursor: nil, has_next: false})
        |> assign(:activity, %{entries: [], next_cursor: nil, has_next: false})
        |> assign(:activity_type, :global)
        |> assign(:activity_pages_loaded, 1)
        |> assign(:activity_top_up_failed, false)
        |> assign(:mobile_tab, :feed)
        |> put_flash(:error, "Could not load the home feed.")
    end
  end

  defp can_top_up?(_activity, _pages_loaded, _failed = true), do: false

  defp can_top_up?(activity, pages_loaded, _failed) do
    pages_loaded < @bounded_max_pages and activity.has_next and
      not is_nil(activity.next_cursor)
  end

  defp feed_review_liked?(items, review_id) do
    Enum.find_value(items, false, fn
      {:review, %{id: ^review_id, liked_by_me: liked?}} -> liked?
      _ -> false
    end)
  end

  defp feed_post_liked?(items, post_id) do
    Enum.find_value(items, false, fn
      {:post, %{id: ^post_id, liked_by_me: liked?}} -> liked?
      _ -> false
    end)
  end

  defp update_review_like(feed, review_id, liked?) do
    update_in(feed.items, fn items ->
      Enum.map(items, fn
        {:review, %{id: ^review_id} = review} ->
          delta = if liked?, do: 1, else: -1

          {:review,
           %{review | liked_by_me: liked?, likes_count: max((review.likes_count || 0) + delta, 0)}}

        item ->
          item
      end)
    end)
  end

  defp update_post_like(feed, post_id, liked?) do
    update_in(feed.items, fn items ->
      Enum.map(items, fn
        {:post, %{id: ^post_id} = post} ->
          delta = if liked?, do: 1, else: -1

          {:post,
           %{post | liked_by_me: liked?, likes_count: max((post.likes_count || 0) + delta, 0)}}

        item ->
          item
      end)
    end)
  end

  defp toggle_review_like(true, review_id, user_id), do: Reviews.unlike_review(review_id, user_id)
  defp toggle_review_like(false, review_id, user_id), do: Reviews.like_review(review_id, user_id)

  defp toggle_post_like(true, post_id, user_id), do: Discussions.unlike_post(post_id, user_id)
  defp toggle_post_like(false, post_id, user_id), do: Discussions.like_post(post_id, user_id)

  defp mobile_tab("activity"), do: :activity
  defp mobile_tab(_), do: :feed

  defp activity_type("following"), do: :following
  defp activity_type(_), do: :global

  defp blank?(value), do: is_nil(value) or (is_binary(value) and String.trim(value) == "")

  # ---------------------------------------------------------------------------
  # Cross-page stitching
  #
  # The server groups consecutive same-(user, action, context) rows within
  # a single page (`Kaguya.Activities.GroupedFeed`). When `load_more`
  # appends another page, a run that straddled the boundary surfaces as
  # two adjacent entries with the same group key — merge them so the
  # rendered count is "X liked 50 covers" instead of "36 + 14". Render-only;
  # never written back to the source data.
  # ---------------------------------------------------------------------------

  @members_display_cap Kaguya.Activities.GroupedFeed.members_cap()
  @stitchable_actions [:liked_screenshot, :liked_cover, :status_changed, :followed]

  defp stitch_adjacent_entries([], new_entries), do: new_entries
  defp stitch_adjacent_entries(existing, []), do: existing

  defp stitch_adjacent_entries(existing, [first_new | rest_new] = new_entries) do
    last_existing = List.last(existing)

    case stitch_pair(last_existing, first_new) do
      :no_match ->
        existing ++ new_entries

      {:ok, merged} ->
        List.replace_at(existing, -1, merged) ++ rest_new
    end
  end

  defp stitch_pair(nil, _), do: :no_match
  defp stitch_pair(_, nil), do: :no_match

  defp stitch_pair(%{members: [rep_a | _]} = a, %{members: [rep_b | _]} = b) do
    case {entry_group_key(rep_a), entry_group_key(rep_b)} do
      {key, key} when not is_nil(key) ->
        members = Enum.take(a.members ++ b.members, @members_display_cap)
        {:ok, %{a | group_size: a.group_size + b.group_size, members: members}}

      _ ->
        :no_match
    end
  end

  defp stitch_pair(_, _), do: :no_match

  defp entry_group_key(%{action: action, actor: %{id: user_id}} = rep)
       when action in @stitchable_actions and is_binary(user_id) do
    metadata = rep.metadata || %{}

    case action do
      a when a in [:liked_screenshot, :liked_cover] ->
        case metadata["vn_slug"] do
          slug when is_binary(slug) -> {user_id, a, slug}
          _ -> nil
        end

      :status_changed ->
        case metadata["status"] do
          status when is_binary(status) -> {user_id, :status_changed, status}
          _ -> nil
        end

      :followed ->
        {user_id, :followed, rep.entity_type}
    end
  end

  defp entry_group_key(_), do: nil
end
