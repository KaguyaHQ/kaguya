defmodule KaguyaWeb.ProfileLive.Recs do
  @moduledoc """
  `/@:username/recs` — personalized VN recommendations.

  Mirrors `../personal/legacy-next-app/src/components/profile/RecommendationsTab.tsx` and
  the `RecommendationList` list variant. Data comes from
  `Kaguya.Recommendations` directly.
  the Next app, not an internal dependency for LiveView.
  """

  use KaguyaWeb.ProfileLive, tab: :recs, title_suffix: "Recommendations"

  alias Kaguya.{Recommendations, Screenshots, VNTags, VisualNovels}
  alias KaguyaWeb.Components.Recommendations.List, as: RecommendationList
  alias KaguyaWeb.Components.Profile.Placeholder

  @limit 25

  @impl Phoenix.LiveView
  def handle_params(%{"username" => raw_username} = params, _uri, socket) do
    username = Data.parse_username(raw_username)
    viewer = socket.assigns[:current_user]

    case Data.load_header(username, viewer) do
      {:ok, profile} ->
        selected_tag_slug = blank_to_nil(params["tag"])
        hide_wishlisted = truthy?(params["hideWishlisted"])
        page = load_recommendations(profile, viewer, selected_tag_slug)

        socket =
          socket
          |> assign(:state, :ready)
          |> assign(:profile, profile)
          |> assign(:permissions, Data.viewer_permissions(viewer))
          |> assign(:page_title, Data.page_title(profile, "Recommendations"))
          |> assign(KaguyaWeb.SEO.noindex())
          |> assign(:selected_tag_slug, selected_tag_slug)
          |> assign(:tag_filter_query, socket.assigns[:tag_filter_query] || "")
          |> assign(:hide_wishlisted, hide_wishlisted)
          |> assign(:is_refreshing, false)
          |> assign_rec_page(page)

        {:noreply, socket}

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

      <section class="px-4 lg:mx-auto lg:max-w-[988px] lg:px-0">
        <RecommendationList.recommendation_list
          recs={@recs}
          tag_counts={@rec_page.tag_counts}
          selected_tag_slug={@selected_tag_slug}
          tag_filter_query={@tag_filter_query}
          hide_wishlisted={@hide_wishlisted}
          show_wishlist_toggle={@profile.viewer.is_logged_in}
          is_own_profile={@profile.viewer.is_mine}
          mode={if @profile.viewer.is_mine, do: :self, else: :other_user}
          signals_count={@rec_page.signals_count}
          signals_required={@rec_page.signals_required}
          is_refreshing={@is_refreshing}
          has_active_filter={@has_active_filter}
          empty_filtered={@empty_filtered}
          current_user={@current_user}
        />
      </section>
    </main>
    """
  end

  @impl Phoenix.LiveView
  def handle_event("set_tag_filter", %{"slug" => slug}, socket) do
    next_tag =
      if socket.assigns.selected_tag_slug == slug do
        nil
      else
        blank_to_nil(slug)
      end

    {:noreply,
     socket
     |> assign(:tag_filter_query, "")
     |> push_patch(
       to: recs_path(socket.assigns.profile, next_tag, socket.assigns.hide_wishlisted)
     )}
  end

  def handle_event("clear_tag_filter", _params, socket) do
    {:noreply,
     socket
     |> assign(:tag_filter_query, "")
     |> push_patch(to: recs_path(socket.assigns.profile, nil, socket.assigns.hide_wishlisted))}
  end

  def handle_event("search_rec_tags", %{"rec_tag_filter" => %{"query" => query}}, socket) do
    {:noreply, assign(socket, :tag_filter_query, tag_filter_query(query))}
  end

  def handle_event("search_rec_tags", %{"query" => query}, socket) do
    {:noreply, assign(socket, :tag_filter_query, tag_filter_query(query))}
  end

  def handle_event("search_rec_tags", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("clear_rec_tag_search", _params, socket) do
    {:noreply, assign(socket, :tag_filter_query, "")}
  end

  def handle_event("toggle_hide_wishlisted", _params, socket) do
    {:noreply,
     push_patch(socket,
       to:
         recs_path(
           socket.assigns.profile,
           socket.assigns.selected_tag_slug,
           !socket.assigns.hide_wishlisted
         )
     )}
  end

  def handle_event("clear_rec_filters", _params, socket) do
    {:noreply,
     socket
     |> assign(:tag_filter_query, "")
     |> push_patch(to: recs_path(socket.assigns.profile, nil, false))}
  end

  def handle_event("refresh_recommendations", _params, socket) do
    if socket.assigns.profile.viewer.is_mine do
      socket = assign(socket, :is_refreshing, true)

      case Recommendations.refresh_for_user(socket.assigns.profile.id) do
        {:ok, _} ->
          page =
            load_recommendations(
              socket.assigns.profile,
              socket.assigns[:current_user],
              socket.assigns.selected_tag_slug
            )

          {:noreply,
           socket
           |> assign(:is_refreshing, false)
           |> assign_rec_page(page)}

        {:error, message} ->
          {:noreply,
           socket
           |> assign(:is_refreshing, false)
           |> put_flash(:error, message)}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("wishlist_rec", %{"vn-id" => vn_id}, socket) do
    mutate_rec(socket, vn_id, &set_rec_status(&1, :want_to_read), fn ->
      Recommendations.wishlist_from_rec(socket.assigns.profile.id, vn_id)
    end)
  end

  def handle_event("undo_wishlist_rec", %{"vn-id" => vn_id}, socket) do
    mutate_rec(socket, vn_id, &set_rec_status(&1, nil), fn ->
      Recommendations.undo_wishlist_from_rec(socket.assigns.profile.id, vn_id)
    end)
  end

  def handle_event("dismiss_rec", %{"vn-id" => vn_id}, socket) do
    mutate_rec(socket, vn_id, &Map.put(&1, :dismissed?, true), fn ->
      Recommendations.dismiss_recommendation(socket.assigns.profile.id, vn_id)
    end)
  end

  def handle_event("undo_dismiss_rec", %{"vn-id" => vn_id}, socket) do
    mutate_rec(socket, vn_id, &Map.put(&1, :dismissed?, false), fn ->
      Recommendations.undo_recommendation_dismiss(socket.assigns.profile.id, vn_id)
    end)
  end

  def handle_event(event, params, socket) do
    super(event, params, socket)
  end

  # ---------------------------------------------------------------------------
  # Rec-card mutations
  # ---------------------------------------------------------------------------

  defp mutate_rec(socket, vn_id, optimistic, mutation) do
    if socket.assigns.profile.viewer.is_mine do
      previous = socket.assigns.rec_page

      socket =
        socket
        |> assign_rec_page(update_rec(previous, vn_id, optimistic))

      case mutation.() do
        {:ok, _} ->
          {:noreply, socket}

        _ ->
          {:noreply,
           socket
           |> assign_rec_page(previous)
           |> put_flash(:error, "Could not update this recommendation.")}
      end
    else
      {:noreply, socket}
    end
  end

  defp update_rec(page, vn_id, fun) do
    items =
      Enum.map(page.items, fn rec ->
        if to_string(rec.visual_novel.id) == to_string(vn_id), do: fun.(rec), else: rec
      end)

    %{page | items: items}
  end

  defp set_rec_status(rec, status),
    do: Map.put(rec, :user_reading_status, if(status, do: %{status: status}, else: nil))

  # ---------------------------------------------------------------------------
  # Loaders
  # ---------------------------------------------------------------------------

  defp load_recommendations(profile, viewer, selected_tag_slug) do
    viewer_id = Data.viewer_id(viewer)

    items =
      profile.id
      |> Recommendations.list_for_user_id(limit: @limit, tag_slug: selected_tag_slug)
      |> Recommendations.hydrate_reasons()
      |> hydrate_recommendation_items(viewer_id)

    %{
      items: items,
      tag_counts: Recommendations.tag_counts_for(profile.id),
      user_max_score: Recommendations.max_score_for(profile.id),
      signals_count: Recommendations.signals_count(profile.id),
      signals_required: Recommendations.min_signals()
    }
  end

  defp hydrate_recommendation_items([], _viewer_id), do: []

  defp hydrate_recommendation_items(items, viewer_id) do
    vn_ids =
      items
      |> Enum.map(& &1.visual_novel.id)
      |> Enum.uniq()

    screenshots_by_vn = Screenshots.list_screenshots_for_vns(viewer_id, vn_ids)
    tags_by_vn = VNTags.list_tags_for_vns(viewer_id, vn_ids)

    Enum.map(items, fn rec ->
      %{
        rank: rec.rank,
        score: rec.score,
        ease_score: rec.ease_score,
        relevance_pct: rec.relevance_pct || 0,
        total_positive_contribution: rec.total_positive_contribution,
        user_signal: rec.user_signal,
        user_reading_status: normalize_status(rec.user_reading_status),
        dismissed?: rec.user_signal == -1,
        visual_novel:
          normalize_vn(
            rec.visual_novel,
            Map.get(screenshots_by_vn, rec.visual_novel.id, []),
            Map.get(tags_by_vn, rec.visual_novel.id, [])
          ),
        because_you_liked: Enum.map(rec.because_you_liked, &normalize_reason/1)
      }
    end)
  end

  defp normalize_vn(vn, screenshots, tags) do
    %{
      id: vn.id,
      title: vn.title,
      slug: vn.slug,
      images: VisualNovels.build_image_urls(vn),
      has_ero: vn.has_ero,
      is_image_nsfw: vn.is_image_nsfw,
      is_image_suggestive: vn.is_image_suggestive,
      screenshots: Enum.map(screenshots, &normalize_screenshot/1),
      tags: Enum.map(tags, &normalize_tag/1)
    }
  end

  defp normalize_screenshot(screenshot) do
    %{
      id: screenshot.id,
      images: VisualNovels.build_screenshot_urls(screenshot.id),
      is_nsfw: Map.get(screenshot, :is_nsfw, false),
      is_brutal: Map.get(screenshot, :is_brutal, false)
    }
  end

  defp normalize_tag(%{tag: tag} = row) do
    %{
      spoiler_level: row[:spoiler_level] || row["spoiler_level"],
      tag: %{
        id: tag.id,
        name: tag.name,
        display_name: Kaguya.Tags.Tag.display_name(tag),
        slug: tag.slug,
        category: tag.category,
        kind: tag.kind
      }
    }
  end

  defp normalize_reason(reason) do
    %{
      user_rating: reason.user_rating,
      user_status: reason.user_status,
      contribution: reason.contribution,
      visual_novel: %{
        id: reason.visual_novel.id,
        title: reason.visual_novel.title,
        slug: reason.visual_novel.slug,
        images: VisualNovels.build_image_urls(reason.visual_novel),
        is_image_nsfw: Map.get(reason.visual_novel, :is_image_nsfw, false),
        is_image_suggestive: Map.get(reason.visual_novel, :is_image_suggestive, false)
      }
    }
  end

  defp normalize_status(nil), do: nil
  defp normalize_status(%{status: status}), do: %{status: status}

  defp assign_rec_page(socket, page) do
    filtered = apply_client_filters(page.items, socket.assigns.hide_wishlisted)

    has_active_filter =
      not is_nil(socket.assigns.selected_tag_slug) or socket.assigns.hide_wishlisted

    socket
    |> assign(:rec_page, page)
    |> assign(:recs, filtered)
    |> assign(:has_active_filter, has_active_filter)
    |> assign(:empty_filtered, filtered == [] and has_active_filter)
  end

  defp apply_client_filters(items, false), do: items

  defp apply_client_filters(items, true),
    do: Enum.reject(items, &wishlisted?/1)

  defp wishlisted?(%{user_reading_status: %{status: status}}),
    do: status in [:want_to_read, "want_to_read", "WANT_TO_READ"]

  defp wishlisted?(_rec), do: false

  # ---------------------------------------------------------------------------
  # Params
  # ---------------------------------------------------------------------------

  defp recs_path(profile, selected_tag_slug, hide_wishlisted) do
    params =
      []
      |> put_param("tag", selected_tag_slug)
      |> put_param("hideWishlisted", if(hide_wishlisted, do: "1", else: nil))

    base = "/@#{profile.username}/recs"

    case URI.encode_query(params) do
      "" -> base
      query -> base <> "?" <> query
    end
  end

  defp put_param(params, _key, nil), do: params
  defp put_param(params, key, value), do: [{key, value} | params]

  defp blank_to_nil(value) when value in [nil, ""], do: nil

  defp blank_to_nil(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp truthy?(value), do: value in [true, "true", "1", 1]

  defp tag_filter_query(nil), do: ""
  defp tag_filter_query(value) when is_binary(value), do: value
  defp tag_filter_query(value), do: to_string(value)
end
