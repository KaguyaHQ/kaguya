defmodule KaguyaWeb.ProfileLive.Reviews do
  @moduledoc """
  `/@:username/reviews` — paginated VN reviews for a user.

  Mirrors the production Next.js source at
  `../personal/legacy-next-app/src/components/profile/ReviewsTab.tsx` + the underlying
  `VnReviewCard` (`../personal/legacy-next-app/src/components/vn/cards/VnReviewCard.tsx`).
  The LiveView reads `Kaguya.Reviews` directly.

  URL state mirrors production:
    * `?page=N`   (1-indexed; omitted when `N=1`)
    * `?sort=…`   (`MOST_LIKED` default, `NEWEST`, `OLDEST`)

  The like toggle is optimistic: the heart and count flip immediately,
  then the mutation runs against `Kaguya.Reviews`. A failure rolls the
  list back and surfaces a flash. Sign-in gating mirrors `ReviewLive.Show`.
  """

  use KaguyaWeb.ProfileLive, tab: :reviews, title_suffix: "Reviews"

  alias Kaguya.Reviews
  alias Kaguya.VisualNovels
  alias Kaguya.VisualNovels.TitleCategory
  alias KaguyaWeb.Components.Profile.Placeholder
  alias KaguyaWeb.Components.Reviews.Cards
  alias KaguyaWeb.ProfileLive.Data

  @page_size 12
  @valid_sorts ~w(MOST_LIKED NEWEST OLDEST)
  @default_sort "MOST_LIKED"

  # ---------------------------------------------------------------------------
  # Params → reviews page
  # ---------------------------------------------------------------------------

  @impl Phoenix.LiveView
  def handle_params(%{"username" => raw_username} = params, _uri, socket) do
    username = Data.parse_username(raw_username)
    viewer = socket.assigns[:current_user]

    case Data.load_header(username, viewer) do
      {:ok, profile} ->
        page = parse_page(params["page"])
        sort = parse_sort(params["sort"])
        reviews = load_reviews(profile, viewer, page, sort)

        {:noreply,
         socket
         |> assign(:state, :ready)
         |> assign(:profile, profile)
         |> assign(:permissions, Data.viewer_permissions(viewer))
         |> assign(:page_title, Data.page_title(profile, "Reviews"))
         |> assign(:reviews, reviews)
         |> assign(:page, reviews.pagination.page)
         |> assign(:sort, sort)
         |> assign(:total_pages, reviews.pagination.total_pages || 1)
         |> assign(:total_count, reviews.pagination.total_count || 0)}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> assign(:state, :not_found)
         |> assign(:page_title, "User not found · Kaguya")}
    end
  end

  # ---------------------------------------------------------------------------
  # Events — like toggle (optimistic) + sort dropdown
  # ---------------------------------------------------------------------------

  @impl Phoenix.LiveView
  def handle_event("toggle_review_like", %{"review-id" => review_id}, socket) do
    case socket.assigns[:current_user] do
      %{id: user_id} ->
        toggle_like_optimistic(socket, review_id, user_id)

      _ ->
        {:noreply, Phoenix.LiveView.put_flash(socket, :error, "Sign in to like reviews.")}
    end
  end

  def handle_event(event, params, socket) do
    super(event, params, socket)
  end

  defp toggle_like_optimistic(socket, review_id, user_id) do
    reviews = socket.assigns.reviews
    target = Enum.find(reviews.items, &(to_string(&1.id) == to_string(review_id)))

    cond do
      is_nil(target) ->
        {:noreply, socket}

      target.liked_by_me ->
        do_toggle(socket, reviews, target, &Reviews.unlike_review(&1, user_id), :unlike)

      true ->
        do_toggle(socket, reviews, target, &Reviews.like_review(&1, user_id), :like)
    end
  end

  defp do_toggle(socket, reviews, target, mutation, direction) do
    delta = if direction == :like, do: 1, else: -1
    optimistic = bump_review(reviews, target.id, delta, direction == :like)
    socket = Phoenix.Component.assign(socket, :reviews, optimistic)

    case mutation.(target.id) do
      {:ok, _} ->
        {:noreply, socket}

      {:error, reason} ->
        rolled_back = bump_review(optimistic, target.id, -delta, direction != :like)

        {:noreply,
         socket
         |> Phoenix.Component.assign(:reviews, rolled_back)
         |> Phoenix.LiveView.put_flash(:error, like_error_message(reason))}
    end
  end

  defp bump_review(reviews, target_id, delta, liked?) do
    items =
      Enum.map(reviews.items, fn item ->
        if to_string(item.id) == to_string(target_id) do
          %{
            item
            | likes_count: max(0, (item.likes_count || 0) + delta),
              liked_by_me: liked?
          }
        else
          item
        end
      end)

    %{reviews | items: items}
  end

  defp like_error_message(reason) when is_binary(reason), do: reason
  defp like_error_message(_), do: "Could not update this like."

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

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
            <%= if @total_count > 0 do %>
              <div class="mb-3 flex w-full items-center justify-between max-lg:gap-2 max-sm:-mt-2 lg:border-b lg:border-[rgb(var(--border-divider))] lg:pb-2">
                <h3 class="text-style-proseMedium text-[rgb(var(--foreground-primary))]">
                  {@profile.display_name}'s reviews
                </h3>
                <.sort_dropdown
                  sort={@sort}
                  base_path={"/@" <> @profile.username <> "/reviews"}
                />
              </div>

              <div class="[&>*:first-child>div]:pt-0 [&>*:last-child>div]:pb-0">
                <Cards.user_review_card :for={review <- @reviews.items} review={review} />
              </div>

              <.reviews_pagination
                :if={@total_pages > 1}
                page={@page}
                total_pages={@total_pages}
                sort={@sort}
                base_path={"/@" <> @profile.username <> "/reviews"}
              />
            <% else %>
              <.empty_reviews />
            <% end %>
          </div>

          <%!-- Right column reserved for future use (matches production). --%>
          <div class="max-lg:hidden" />
        </div>
      </section>
    </main>
    """
  end

  # ---------------------------------------------------------------------------
  # Inline function components
  # ---------------------------------------------------------------------------

  attr :sort, :string, required: true
  attr :base_path, :string, required: true

  defp sort_dropdown(assigns) do
    ~H"""
    <KaguyaWeb.UI.Menu.menu
      id="profile-reviews-sort"
      align="end"
      class="flex h-full w-fit cursor-pointer items-center gap-2 p-0 text-sm leading-none font-medium text-[rgb(var(--foreground-secondary))] transition hover:text-[rgb(var(--foreground-primary))] max-sm:h-fit max-sm:text-[15px] max-sm:leading-[18px]"
    >
      <:trigger aria-label="Sort reviews">
        <span>{sort_label(@sort)}</span>
        <Lucide.chevron_down class="size-4 shrink-0" aria-hidden />
      </:trigger>
      <div class="w-auto min-w-32 overflow-hidden rounded-[8px] border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-menu-item-default))] p-0 text-[rgb(var(--foreground-primary))] shadow-lg">
        <.link
          data-menu-dismiss
          patch={sort_patch(@base_path, "MOST_LIKED")}
          class={sort_option_class(@sort == "MOST_LIKED")}
          aria-current={if @sort == "MOST_LIKED", do: "true"}
        >
          Popular
        </.link>
        <.link
          data-menu-dismiss
          patch={sort_patch(@base_path, "NEWEST")}
          class={sort_option_class(@sort == "NEWEST")}
          aria-current={if @sort == "NEWEST", do: "true"}
        >
          Newest
        </.link>
        <.link
          data-menu-dismiss
          patch={sort_patch(@base_path, "OLDEST")}
          class={sort_option_class(@sort == "OLDEST")}
          aria-current={if @sort == "OLDEST", do: "true"}
        >
          Oldest
        </.link>
      </div>
    </KaguyaWeb.UI.Menu.menu>
    """
  end

  attr :page, :integer, required: true
  attr :total_pages, :integer, required: true
  attr :sort, :string, required: true
  attr :base_path, :string, required: true

  defp reviews_pagination(assigns) do
    assigns = assign(assigns, :pages, pagination_pages(assigns.page, assigns.total_pages))

    ~H"""
    <nav class="mt-4 flex flex-wrap items-center justify-center gap-1.5 text-sm text-[rgb(var(--foreground-secondary))]">
      <span :if={@page == 1} class={pagination_disabled_class()}>Previous</span>
      <.link
        :if={@page > 1}
        patch={page_patch(@base_path, @page - 1, @sort)}
        class={pagination_step_class()}
      >
        Previous
      </.link>

      <%= for entry <- @pages do %>
        <span :if={entry == :gap} class="px-1.5 text-[rgb(var(--foreground-quaternary))]">…</span>
        <span :if={entry == @page} class={pagination_current_class()} aria-current="page">
          {entry}
        </span>
        <.link
          :if={is_integer(entry) and entry != @page}
          patch={page_patch(@base_path, entry, @sort)}
          class={pagination_number_class()}
        >
          {entry}
        </.link>
      <% end %>

      <span :if={@page >= @total_pages} class={pagination_disabled_class()}>Next</span>
      <.link
        :if={@page < @total_pages}
        patch={page_patch(@base_path, @page + 1, @sort)}
        class={pagination_step_class()}
      >
        Next
      </.link>
    </nav>
    """
  end

  defp empty_reviews(assigns) do
    ~H"""
    <div class="flex min-h-[180px] items-center justify-center rounded-lg border border-[rgb(var(--border-divider))]">
      <p class="text-sm text-[rgb(var(--foreground-secondary))]">No reviews yet.</p>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Data loader
  # ---------------------------------------------------------------------------

  defp load_reviews(profile, viewer, page, sort) do
    sort_by = sort_to_atom(sort)
    viewer_id = Map.get(viewer || %{}, :id)
    allowed = allowed_categories(profile, viewer, viewer_id)

    opts = if allowed, do: [allowed_categories: allowed], else: []

    {:ok, %{items: items, pagination: pagination}} =
      Reviews.list_reviews_for_user(
        profile.id,
        %{page: page, page_size: @page_size, sort_by: sort_by},
        viewer_id,
        opts
      )

    items = preload_visual_novels(items)
    liked_ids = liked_set(viewer_id, items)
    owner = owner_view(profile)

    normalized = Enum.map(items, &normalize_review(&1, owner, liked_ids))

    %{
      items: normalized,
      pagination: %{
        page: pagination.page,
        page_size: pagination.page_size,
        total_count: Kaguya.Pagination.resolve_count(pagination),
        total_pages: Kaguya.Pagination.resolve_total_pages(pagination)
      }
    }
  end

  defp allowed_categories(%{viewer: %{is_mine: true}}, _viewer, _viewer_id), do: nil

  defp allowed_categories(_profile, viewer, _viewer_id),
    do: TitleCategory.allowed_categories(viewer || %{})

  defp preload_visual_novels(items) do
    Kaguya.Repo.preload(items, :visual_novel)
  end

  defp liked_set(nil, _items), do: MapSet.new()

  defp liked_set(viewer_id, items) do
    ids = Enum.map(items, & &1.id)

    viewer_id
    |> Reviews.liked_review_ids_in(ids)
    |> MapSet.new(&to_string/1)
  end

  defp owner_view(%{username: u, display_name: d}),
    do: %{username: u, display_name: d || u}

  defp normalize_review(review, owner, liked_ids) do
    %{
      id: review.id,
      content: review.content,
      rating: review.rating,
      likes_count: review.likes_count || 0,
      comments_count: review.comments_count || 0,
      liked_by_me: MapSet.member?(liked_ids, to_string(review.id)),
      is_spoiler: review.is_spoiler,
      is_edited: review.is_edited,
      inserted_at: review.inserted_at,
      user: owner,
      visual_novel: normalize_vn(review.visual_novel)
    }
  end

  defp normalize_vn(nil), do: nil

  defp normalize_vn(%Kaguya.VisualNovels.VisualNovel{} = vn) do
    %{
      id: vn.id,
      slug: vn.slug,
      title: vn.title,
      has_ero: vn.has_ero,
      images: VisualNovels.build_image_urls(vn),
      is_image_nsfw: vn.is_image_nsfw,
      is_image_suggestive: vn.is_image_suggestive
    }
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp parse_page(nil), do: 1

  defp parse_page(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n >= 1 -> n
      _ -> 1
    end
  end

  defp parse_page(value) when is_integer(value) and value >= 1, do: value
  defp parse_page(_), do: 1

  defp parse_sort(value) when value in @valid_sorts, do: value
  defp parse_sort(_), do: @default_sort

  defp sort_to_atom("MOST_LIKED"), do: :most_liked
  defp sort_to_atom("NEWEST"), do: :newest
  defp sort_to_atom("OLDEST"), do: :oldest
  defp sort_to_atom(_), do: :most_liked

  defp sort_label("NEWEST"), do: "Newest"
  defp sort_label("OLDEST"), do: "Oldest"
  defp sort_label(_), do: "Popular"

  defp sort_patch(base_path, "MOST_LIKED"), do: base_path
  defp sort_patch(base_path, sort), do: "#{base_path}?sort=#{sort}"

  defp page_patch(base_path, 1, "MOST_LIKED"), do: base_path
  defp page_patch(base_path, 1, sort), do: "#{base_path}?sort=#{sort}"
  defp page_patch(base_path, page, "MOST_LIKED"), do: "#{base_path}?page=#{page}"
  defp page_patch(base_path, page, sort), do: "#{base_path}?page=#{page}&sort=#{sort}"

  defp sort_option_class(true) do
    "block h-auto bg-[rgb(var(--surface-menu-item-hover))] px-3.5 py-3 text-sm leading-[17px] font-medium text-[rgb(var(--foreground-primary))]"
  end

  defp sort_option_class(false) do
    "block h-auto bg-[rgb(var(--surface-menu-item-default))] px-3.5 py-3 text-sm leading-[17px] font-medium text-[rgb(var(--foreground-primary))] transition hover:bg-[rgb(var(--surface-menu-item-hover))] active:bg-[rgb(var(--surface-menu-item-pressed))]"
  end

  # Pagination layout — matches `KaguyaWeb.VN.Community`.
  defp pagination_pages(_page, total_pages) when total_pages <= 7,
    do: Enum.to_list(1..total_pages)

  defp pagination_pages(page, total_pages) do
    middle_start = max(page - 1, 2)
    middle_end = min(page + 1, total_pages - 1)
    middle = Enum.to_list(middle_start..middle_end)

    [1]
    |> maybe_add_gap(List.first(middle))
    |> Kernel.++(middle)
    |> maybe_add_gap(total_pages, List.last(middle))
    |> Kernel.++([total_pages])
  end

  defp maybe_add_gap(pages, next_page) when is_integer(next_page) and next_page > 2,
    do: pages ++ [:gap]

  defp maybe_add_gap(pages, _next_page), do: pages

  defp maybe_add_gap(pages, total_pages, previous_page)
       when is_integer(previous_page) and previous_page < total_pages - 1,
       do: pages ++ [:gap]

  defp maybe_add_gap(pages, _total_pages, _previous_page), do: pages

  defp pagination_step_class do
    "rounded-full border border-[rgb(var(--chip-border-default))] px-3 py-1.5 transition hover:border-[rgb(var(--chip-border-hover))] hover:text-[rgb(var(--foreground-primary))]"
  end

  defp pagination_number_class do
    "flex size-8 items-center justify-center rounded-full border border-[rgb(var(--chip-border-default))] text-xs transition hover:border-[rgb(var(--chip-border-hover))] hover:text-[rgb(var(--foreground-primary))]"
  end

  defp pagination_current_class do
    "flex size-8 items-center justify-center rounded-full border border-[rgb(var(--foreground-secondary))] bg-white/[4%] text-xs font-medium text-[rgb(var(--foreground-primary))]"
  end

  defp pagination_disabled_class do
    "rounded-full border border-[rgb(var(--border-divider))] px-3 py-1.5 text-[rgb(var(--foreground-quaternary))]"
  end
end
