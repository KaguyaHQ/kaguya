defmodule KaguyaWeb.VNLive.Ratings do
  use KaguyaWeb, :live_view

  import KaguyaWeb.Components.Shared.RatingsChart, only: [ratings_chart: 1]
  import KaguyaWeb.SharedComponents.UserListRow, only: [user_list_row: 1]
  import KaguyaWeb.SharedComponents.LoadMore
  import KaguyaWeb.UI.Menu
  import KaguyaWeb.VN.Formatters, only: [format_count: 2, with_commas: 1]
  import KaguyaWeb.VN.Icons, only: [display_ratings: 1]

  alias Kaguya.{Social, VisualNovels}
  alias Kaguya.Users
  alias KaguyaWeb.Components.Shared.NotFoundPage
  alias KaguyaWeb.SharedComponents.Time, as: SharedTime

  @limit 20
  @rating_options Enum.reverse(Kaguya.RatingDistribution.valid_rating_values())

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(KaguyaWeb.SEO.noindex())
     |> assign(
       slug: nil,
       rating: nil,
       rating_param: nil,
       vn: nil,
       raters: [],
       next_cursor: nil,
       has_next: false,
       page_title: "Ratings • Kaguya",
       loading: true,
       not_found?: false
     )}
  end

  @impl true
  def handle_params(%{"slug" => slug, "rating" => rating_param}, _uri, socket) do
    with {:ok, rating} <- parse_rating(rating_param),
         {:ok, vn} <- get_vn(slug, socket.assigns.current_user),
         {:ok, page} <- VisualNovels.list_users_who_rated_vn(vn.id, rating, nil, @limit) do
      {:noreply,
       assign(socket,
         slug: slug,
         rating: rating,
         rating_param: rating_path(rating),
         vn: normalize_vn(vn),
         raters: normalize_raters(page.items, socket.assigns.current_user),
         next_cursor: page.next_cursor,
         has_next: page.has_next,
         page_title: "Ratings for '#{vn.title}' • Kaguya",
         loading: false
       )}
    else
      _ ->
        {:noreply,
         assign(socket,
           slug: slug,
           page_title: "Visual novel not found · Kaguya",
           not_found?: true,
           loading: false
         )}
    end
  end

  @impl true
  def handle_event("load_more", _params, socket) do
    with true <- socket.assigns.has_next,
         {:ok, page} <-
           VisualNovels.list_users_who_rated_vn(
             socket.assigns.vn.id,
             socket.assigns.rating,
             socket.assigns.next_cursor,
             @limit
           ) do
      {:noreply,
       assign(socket,
         raters:
           socket.assigns.raters ++ normalize_raters(page.items, socket.assigns.current_user),
         next_cursor: page.next_cursor,
         has_next: page.has_next
       )}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("follow_user", %{"user-id" => id}, socket) do
    case socket.assigns.current_user do
      %{id: viewer_id} ->
        _ = Social.follow_user(viewer_id, id)
        {:noreply, update_rater_follow(socket, id)}

      _ ->
        redirect_to = "/vn/#{socket.assigns.slug}/ratings/#{socket.assigns.rating_param}"
        {:noreply, push_navigate(socket, to: ~p"/login?#{[redirectTo: redirect_to]}")}
    end
  end

  def handle_event("unfollow_user", %{"user-id" => id}, socket) do
    case socket.assigns.current_user do
      %{id: viewer_id} ->
        _ = Social.unfollow_user(viewer_id, id)
        {:noreply, update_rater_follow(socket, id)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def render(%{not_found?: true} = assigns) do
    ~H"""
    <NotFoundPage.not_found_page variant={:overlay} />
    """
  end

  def render(assigns) do
    ~H"""
    <main class="min-h-[calc(100vh-172px)] bg-[rgb(var(--surface-base))] pb-[110px] text-[rgb(var(--foreground-primary))] sm:pb-32 lg:pb-[88px]">
      <div class="mx-auto mt-6 max-w-[937px] px-4 md:mt-8 md:px-0 lg:mt-[48px]">
        <%= if @loading or is_nil(@vn) do %>
          <p class="py-16 text-sm text-[rgb(var(--foreground-tertiary))]">Loading ratings...</p>
        <% else %>
          <div class="flex items-center gap-3 border-b border-[rgb(var(--border-divider))] pb-4 lg:hidden">
            <.cover_thumb vn={@vn} size="w-[67px]" rounded="rounded-[2px]" sizes="67px" />
            <div class="min-w-0">
              <p class="text-sm leading-[17px] text-[rgb(var(--foreground-secondary))]">
                Everyone who has rated
              </p>
              <.link
                navigate={~p"/vn/#{@vn.slug}"}
                class="line-clamp-2 w-fit text-lg leading-[22px] font-semibold text-[rgb(var(--foreground-primary))]"
                style="font-family: var(--font-source-serif)"
              >
                {@vn.title}
              </.link>
              <.rating_selector
                id="rating-selector-desktop"
                slug={@vn.slug}
                rating={@rating}
                ratings_dist={@vn.ratings_dist}
                class="mt-2"
              />
            </div>
          </div>

          <div class="grid w-full grid-cols-1 gap-16 lg:grid-cols-[669px_204px]">
            <section class="min-w-0">
              <div class="hidden items-end justify-between border-b border-[rgb(var(--border-divider))] pb-4 lg:flex">
                <div class="flex flex-col gap-1">
                  <span class="text-base leading-[19px] text-[rgb(var(--foreground-secondary))]">
                    Everyone who has rated
                  </span>
                  <.link
                    navigate={~p"/vn/#{@vn.slug}"}
                    class="w-fit text-2xl leading-[29px] font-semibold text-[rgb(var(--foreground-primary))] hover:text-[rgb(var(--text-link-hover))]"
                    style="font-family: var(--font-source-serif)"
                  >
                    {@vn.title}
                  </.link>
                </div>
                <.rating_selector
                  id="rating-selector-mobile"
                  slug={@vn.slug}
                  rating={@rating}
                  ratings_dist={@vn.ratings_dist}
                />
              </div>

              <div class="flex flex-col divide-y divide-[#98C6F4]/10">
                <%= if @raters == [] do %>
                  <p class="mt-6 text-center text-sm text-[rgb(var(--foreground-secondary))]">
                    No users found for this rating
                  </p>
                <% else %>
                  <.rater_row :for={row <- @raters} row={row} slug={@vn.slug} />
                <% end %>
              </div>

              <div :if={@has_next} class="mt-6 flex justify-center">
                <.load_more label="Load more" phx-click="load_more" />
              </div>
            </section>

            <aside class="hidden lg:block">
              <.cover_thumb vn={@vn} size="w-[204px]" rounded="rounded-[8px]" sizes="204px" />
              <div class="mt-6">
                <.ratings_chart
                  dist={@vn.ratings_dist}
                  count={@vn.ratings_count}
                  average={@vn.average_rating || 0.0}
                  vn_slug={@vn.slug}
                  hide_title
                />
                <p class="mt-3 text-center text-xs text-[rgb(var(--foreground-tertiary))]">
                  {format_count(@vn.ratings_count, "rating")}
                </p>
              </div>
            </aside>
          </div>
        <% end %>
      </div>
    </main>
    """
  end

  attr :id, :string, required: true
  attr :slug, :string, required: true
  attr :rating, :float, required: true
  attr :ratings_dist, :any, default: %{}
  attr :class, :any, default: nil

  defp rating_selector(assigns) do
    assigns = assign(assigns, :rating_options, @rating_options)

    ~H"""
    <.menu
      id={@id}
      align="end"
      class={["flex cursor-pointer items-center gap-1 leading-none", @class]}
    >
      <:trigger aria-label="Filter by rating">
        <.display_ratings rating={@rating} class="gap-0.5" star_class="text-[13px] leading-none" />
        <Lucide.chevron_down
          class="size-3 shrink-0 text-[rgb(var(--foreground-secondary))]"
          aria-hidden="true"
        />
      </:trigger>
      <div class="w-[150px] rounded-[8px] border border-white/8 bg-[rgb(var(--surface-elevated))] p-1 shadow-[0_14px_30px_rgba(0,0,0,0.3)]">
        <.link
          :for={option <- @rating_options}
          data-menu-dismiss
          navigate={~p"/vn/#{@slug}/ratings/#{rating_path(option)}"}
          class={[
            "flex h-9 items-center justify-between rounded-[6px] px-3 transition hover:bg-white/4",
            option == @rating && "bg-white/6"
          ]}
          aria-current={if option == @rating, do: "true"}
        >
          <.display_ratings rating={option} class="gap-0.5" star_class="text-[12px] leading-none" />
          <span
            :if={rating_count(@ratings_dist, option) > 0}
            class="text-xs text-[rgb(var(--foreground-tertiary))] tabular-nums"
          >
            {with_commas(rating_count(@ratings_dist, option))}
          </span>
        </.link>
      </div>
    </.menu>
    """
  end

  attr :row, :map, required: true
  attr :slug, :string, required: true

  defp rater_row(assigns) do
    ~H"""
    <.user_list_row user={@row.user} follow_value_name="user-id">
      <:meta>
        <.display_ratings
          rating={@row.rating}
          class="w-[80px] gap-0.5 max-lg:hidden"
          star_class="text-[12px] leading-none"
        />
        <time
          title={SharedTime.datetime_title(@row.rated_at)}
          class="line-clamp-1 h-fit self-center text-[11px] leading-[13px] text-[rgb(var(--foreground-secondary))] lg:text-[13px] lg:leading-[16px]"
        >
          {SharedTime.calendar_custom(@row.rated_at)}
        </time>
        <.link
          :if={@row.review?}
          navigate={~p"/@#{@row.user.username}/reviews/#{@slug}"}
          class="flex size-6 items-center justify-center text-[rgb(var(--foreground-secondary))] hover:text-[rgb(var(--foreground-primary))]"
          aria-label="Review"
          title="Review"
        >
          <Lucide.message_square_text class="size-3" aria-hidden="true" />
        </.link>
        <div :if={!@row.review?} class="size-6" />
      </:meta>
    </.user_list_row>
    """
  end

  attr :vn, :map, required: true
  attr :size, :string, required: true
  attr :rounded, :string, required: true
  attr :sizes, :string, required: true

  defp cover_thumb(assigns) do
    ~H"""
    <.link
      navigate={"/vn/#{@vn.slug}"}
      class={["block aspect-2/3 overflow-hidden border border-white/12", @size, @rounded]}
      style="box-shadow: 0px 2px 6px rgba(0, 0, 0, 0.40)"
    >
      <KaguyaWeb.SharedComponents.Cover.cover
        vn={@vn}
        sizes={@sizes}
        class={@rounded}
        fallback_class={@rounded}
      />
    </.link>
    """
  end

  defp get_vn(slug, viewer) do
    case VisualNovels.get_visual_novel_by_slug(slug, viewer_opts(viewer)) do
      nil -> {:error, :not_found}
      vn -> {:ok, vn}
    end
  end

  defp viewer_opts(%{role: role}) when role in [:moderator, :admin], do: [include_hidden: true]
  defp viewer_opts(_), do: []

  defp normalize_vn(vn) do
    %{
      id: vn.id,
      slug: vn.slug,
      title: vn.title,
      average_rating: vn.average_rating || 0.0,
      ratings_count: vn.ratings_count || 0,
      ratings_dist: Kaguya.RatingDistribution.convert_ratings_dist(vn.ratings_dist),
      images: VisualNovels.build_image_urls(vn),
      is_image_nsfw: Map.get(vn, :is_image_nsfw, false),
      is_image_suggestive: Map.get(vn, :is_image_suggestive, false)
    }
  end

  defp normalize_raters(items, viewer) do
    viewer_id = viewer && viewer.id
    followed_ids = followed_ids(viewer_id, items)

    Enum.map(items, fn item ->
      user = item.user
      avatar_urls = Users.build_avatar_urls(user.avatar_id)

      %{
        id: item.id,
        rating: item.rating,
        rated_at: item.rated_at,
        review?: not is_nil(item.review),
        user: %{
          id: user.id,
          username: user.username,
          display_name: user.display_name || user.username,
          avatar_urls: avatar_urls,
          avatar_url: avatar_urls[:small],
          follow_state: follow_state(user.id, viewer_id, followed_ids)
        }
      }
    end)
  end

  defp followed_ids(nil, _items), do: MapSet.new()

  defp followed_ids(viewer_id, items) do
    target_ids = items |> Enum.map(& &1.user.id) |> Enum.uniq()
    Social.batch_followed_ids(viewer_id, target_ids)
  end

  defp follow_state(user_id, viewer_id, _followed_ids) when user_id == viewer_id, do: :self

  defp follow_state(user_id, _viewer_id, followed_ids),
    do: if(MapSet.member?(followed_ids, user_id), do: :following, else: :not_following)

  defp update_rater_follow(socket, id) do
    viewer = socket.assigns.current_user

    update(socket, :raters, fn raters ->
      Enum.map(raters, fn
        %{user: %{id: ^id} = user} = row ->
          put_in(row, [:user, :follow_state], Social.follow_state(viewer.id, user.id))

        row ->
          row
      end)
    end)
  end

  defp parse_rating(value) when is_binary(value) do
    normalized =
      value
      |> String.trim()
      |> String.upcase()
      |> String.replace_prefix("RATING_", "")
      |> String.replace("_", ".")
      |> String.downcase()

    case Float.parse(normalized) do
      {rating, ""} when rating in @rating_options -> {:ok, rating}
      _ -> :error
    end
  end

  defp parse_rating(_), do: :error

  defp rating_path(rating) when rating == trunc(rating), do: Integer.to_string(trunc(rating))
  defp rating_path(rating), do: :erlang.float_to_binary(rating * 1.0, decimals: 1)

  defp rating_count(dist, rating) when is_map(dist) do
    decimal_key = :erlang.float_to_binary(rating * 1.0, decimals: 1)

    keys =
      if rating == trunc(rating) do
        [decimal_key, rating_path(rating)]
      else
        [decimal_key]
      end

    Enum.reduce(keys, 0, fn key, acc -> acc + (Map.get(dist, key) || 0) end)
  end

  defp rating_count(_dist, _rating), do: 0
end
