defmodule KaguyaWeb.ReviewLive.Show do
  @moduledoc """
  LiveView for the single-review page (`/@:username/reviews/:vn_slug`).

  Mirrors the Next.js implementation at
  `../personal/legacy-next-app/src/app/(main)/(maxWidthWrapper)/users/[username]/reviews/[vnSlug]/page.tsx`:

    * Server-rendered first paint with route-specific metadata. Review JSON-LD
      is emitted as a Phoenix-side SEO addition using a Google-supported
      `VideoGame` reviewed item.
    * Reads `?page=` and `?sort=` for the embedded comments tree and
      drives them through `push_patch` so back/forward navigation works.
    * Mutations (like, edit, delete, hide, lock) go through the
      `Kaguya.Reviews` context.
    * Comments live entirely inside `KaguyaWeb.CommentsComponent` with
      `KaguyaWeb.Comments.ReviewAdapter` — this LV doesn't handle comment
      CRUD.
  """

  use KaguyaWeb, :live_view

  alias Kaguya.Reviews
  alias KaguyaWeb.Comments.ReviewAdapter
  alias KaguyaWeb.CommentsComponent
  alias KaguyaWeb.Components.Shared.NotFoundPage
  alias KaguyaWeb.ReviewLive.Data
  alias KaguyaWeb.Reviews.ShowComponents
  alias KaguyaWeb.SEO

  @base_url "https://kaguya.io"
  @comments_page_size 10
  @sort_options ~w(newest oldest most_liked)

  # ---------------------------------------------------------------------------
  # Mount / params
  # ---------------------------------------------------------------------------

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       state: :loading,
       page_title: "Review · Kaguya",
       review: nil,
       vn: nil,
       owner: nil,
       more_reviews: [],
       is_mine: false,
       can_moderate: false,
       liked_by_me: false,
       comments_page: 1,
       comments_sort: "newest",
       comments_page_size: @comments_page_size,
       base_path: "/",
       base_path_with_sort: "/",
       share_url: @base_url,
       json_ld: nil,
       edit_dialog_open: false,
       edit_saving: false,
       edit_error: nil,
       route: nil
     )}
  end

  @impl true
  def handle_params(%{"username" => username, "vn_slug" => slug} = params, _uri, socket) do
    comments_page = parse_page(params["page"])
    comments_sort = normalize_sort(params["sort"])

    socket =
      socket
      |> assign(:comments_page, comments_page)
      |> assign(:comments_sort, comments_sort)
      |> load_page(username, slug)

    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(%{state: :not_found} = assigns) do
    ~H"""
    <NotFoundPage.not_found_page variant={:overlay} />
    """
  end

  def render(%{state: :loading} = assigns) do
    ~H"""
    <main class="bg-surface-base text-foreground-primary min-h-screen">
      <section class="text-foreground-secondary mx-auto max-w-[988px] px-4 py-20 text-sm">
        Loading review…
      </section>
    </main>
    """
  end

  def render(assigns) do
    ~H"""
    <main class="bg-surface-base text-foreground-primary min-h-screen">
      <section class="mx-auto mt-10 mb-[110px] max-w-[988px] gap-x-[44px] sm:mb-40 lg:grid lg:grid-cols-[1fr_180px] lg:px-0">
        <div class="flex flex-col lg:gap-12">
          <%!--
            Header + body + actions are grouped in one block so the parent
            `lg:gap-12` only spaces the comments/more-reviews sections away
            from this entire review unit (matches Next.js SingleReview.tsx).
          --%>
          <div>
            <ShowComponents.review_header :if={@review} review={@review} vn={@vn} owner={@owner} />
            <ShowComponents.mobile_header :if={@review} review={@review} vn={@vn} owner={@owner} />

            <div class="px-4 lg:px-0">
              <ShowComponents.hidden_banner :if={@review.is_hidden} />

              <ShowComponents.review_body review={@review} class="mt-5 max-lg:mt-4" />

              <ShowComponents.actions_bar
                review={@review}
                liked_by_me={@liked_by_me}
                is_mine={@is_mine}
                can_moderate={@can_moderate}
                is_logged_in={!is_nil(@current_user)}
                share_url={@share_url}
              />
            </div>
          </div>

          <%!--
            Comments section header lives in the LV (prod renders it in the
            page, not inside the comments component) so we can match
            `SingleReview.tsx`'s typography and the separator that's only
            visible on desktop.
          --%>
          <section id="comments" class="pt-6 sm:max-lg:mb-5 lg:pt-0">
            <div class="flex items-center justify-between gap-4 max-lg:mb-4 max-lg:px-5">
              <h3 class="sm:text-style-body1Medium text-foreground-primary text-base">
                <span :if={@review.comments_count > 0} class="text-style-body1Medium max-sm:hidden">
                  {@review.comments_count}
                </span>
                {pluralize_comments(@review.comments_count)}
                <span
                  :if={@review.comments_count > 0}
                  class="text-foreground-primary/40 font-medium sm:hidden"
                >
                  ({@review.comments_count})
                </span>
              </h3>
            </div>

            <hr class="border-border-divider mt-1.5 mb-[30px] border-t max-lg:hidden" />

            <ShowComponents.locked_banner :if={@review.is_locked} />

            <.live_component
              module={CommentsComponent}
              id={"review-comments-#{@review.id}"}
              adapter={ReviewAdapter}
              resource_id={@review.id}
              current_user={@current_user}
              page={@comments_page}
              page_size={@comments_page_size}
              base_path={@base_path_with_sort <> "#comments"}
              page_param="page"
              locked={@review.is_locked}
              hide_header={true}
            />
          </section>

          <ShowComponents.more_reviews_grid
            :if={@more_reviews != []}
            owner={@owner}
            items={@more_reviews}
          />
        </div>

        <aside class="h-fit max-lg:hidden">
          <ShowComponents.cover_panel :if={@vn} vn={@vn} />
        </aside>
      </section>

      <ShowComponents.edit_dialog
        :if={@edit_dialog_open}
        review={@review}
        saving={@edit_saving}
        error_message={@edit_error}
      />
    </main>
    """
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("toggle_like", _params, socket) do
    was_liked? = socket.assigns.liked_by_me
    next_liked? = not was_liked?

    with %{id: user_id} <- socket.assigns.current_user,
         socket = apply_local_like(socket, next_liked?),
         {:ok, _} <- toggle_like(was_liked?, socket.assigns.review.id, user_id) do
      {:noreply, socket}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Sign in to like reviews.")}

      {:error, reason} ->
        {:noreply,
         socket
         |> apply_local_like(was_liked?)
         |> put_flash(:error, error_message(reason))}
    end
  end

  def handle_event("open_edit", _params, socket) do
    if socket.assigns.is_mine and not socket.assigns.review.is_locked do
      {:noreply, assign(socket, edit_dialog_open: true, edit_error: nil)}
    else
      {:noreply, put_flash(socket, :error, "You can't edit this review.")}
    end
  end

  def handle_event("close_edit", _params, socket) do
    {:noreply, assign(socket, edit_dialog_open: false, edit_error: nil)}
  end

  def handle_event("submit_edit", params, socket) do
    with %{id: user_id} <- socket.assigns.current_user,
         true <- socket.assigns.is_mine,
         %{} = review <- socket.assigns.review,
         attrs <- edit_attrs(params),
         socket <- assign(socket, edit_saving: true),
         {:ok, _updated} <- Reviews.update_review(review.id, user_id, attrs) do
      {:noreply,
       socket
       |> assign(edit_dialog_open: false, edit_saving: false, edit_error: nil)
       |> reload_current()}
    else
      false ->
        {:noreply,
         socket
         |> assign(edit_saving: false)
         |> put_flash(:error, "Only the review author can edit this review.")}

      nil ->
        {:noreply, socket |> assign(edit_saving: false) |> put_flash(:error, "Sign in to edit.")}

      {:error, reason} ->
        {:noreply, assign(socket, edit_saving: false, edit_error: error_message(reason))}
    end
  end

  def handle_event("confirm_delete", _params, socket) do
    with %{id: user_id} <- socket.assigns.current_user,
         true <- socket.assigns.is_mine,
         %{} = review <- socket.assigns.review,
         {:ok, true} <- Reviews.delete_review(review.id, user_id) do
      {:noreply,
       socket
       |> put_flash(:info, "Review deleted.")
       |> push_navigate(to: "/vn/#{socket.assigns.vn.slug}")}
    else
      false ->
        {:noreply, put_flash(socket, :error, "Only the review author can delete this review.")}

      nil ->
        {:noreply, put_flash(socket, :error, "Sign in to delete this review.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, error_message(reason))}
    end
  end

  def handle_event("toggle_hidden", _params, socket) do
    with true <- socket.assigns.can_moderate,
         false <- socket.assigns.is_mine,
         %{} = review <- socket.assigns.review,
         {:ok, _} <- toggle_hidden(review) do
      {:noreply, reload_current(socket)}
    else
      false ->
        {:noreply, put_flash(socket, :error, "Moderators can't moderate their own review.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Moderator access is required.")}
    end
  end

  def handle_event("toggle_locked", _params, socket) do
    with true <- socket.assigns.can_moderate,
         %{} = review <- socket.assigns.review,
         {:ok, _} <- toggle_locked(review) do
      {:noreply, reload_current(socket)}
    else
      _ -> {:noreply, put_flash(socket, :error, "Moderator access is required.")}
    end
  end

  # ---------------------------------------------------------------------------
  # Internals
  # ---------------------------------------------------------------------------

  defp load_page(socket, username, slug) do
    case Data.load_show_page(username, slug, viewer: socket.assigns.current_user) do
      {:ok, payload} -> assign_payload(socket, username, slug, payload)
      {:error, _reason} -> assign_not_found(socket)
    end
  end

  defp assign_payload(socket, username, slug, payload) do
    base_path = "/@#{username}/reviews/#{slug}"
    sort = socket.assigns.comments_sort

    socket
    |> assign(:state, :loaded)
    |> assign(:route, %{username: username, slug: slug})
    |> assign(:review, payload.review)
    |> assign(:vn, payload.vn)
    |> assign(:owner, payload.owner)
    |> assign(:more_reviews, payload.more_reviews)
    |> assign(:is_mine, payload.is_mine)
    |> assign(:can_moderate, payload.can_moderate)
    |> assign(:liked_by_me, payload.liked_by_me)
    |> assign(:base_path, base_path)
    |> assign(:base_path_with_sort, append_sort(base_path, sort))
    |> assign(:share_url, @base_url <> base_path)
    |> assign(build_seo(payload, base_path))
  end

  defp assign_not_found(socket) do
    assign(socket,
      state: :not_found,
      review: nil,
      vn: nil,
      owner: nil,
      page_title: "Review Not Found · Kaguya",
      meta_description: "The review you are looking for does not exist.",
      canonical_url: nil,
      og_title: "Review Not Found · Kaguya",
      og_description: "The review you are looking for does not exist.",
      og_url: nil,
      og_image: nil,
      twitter_title: "Review Not Found · Kaguya",
      twitter_description: "The review you are looking for does not exist.",
      twitter_image: nil,
      json_ld: nil
    )
  end

  defp reload_current(socket) do
    case socket.assigns.route do
      %{username: u, slug: s} -> load_page(socket, u, s)
      _ -> socket
    end
  end

  defp toggle_like(true, review_id, user_id), do: Reviews.unlike_review(review_id, user_id)
  defp toggle_like(false, review_id, user_id), do: Reviews.like_review(review_id, user_id)

  defp apply_local_like(socket, liked?) do
    review = socket.assigns.review
    delta = if liked?, do: 1, else: -1
    new_count = max((review.likes_count || 0) + delta, 0)

    assign(socket,
      liked_by_me: liked?,
      review: %{review | likes_count: new_count}
    )
  end

  defp toggle_hidden(%{is_hidden: true, id: id}), do: Reviews.unhide_review(id)

  defp toggle_hidden(%{id: id}),
    do: Reviews.hide_review(id, %{reason: "Hidden from LiveView moderation action"})

  defp toggle_locked(%{is_locked: true, id: id}), do: Reviews.admin_unlock_review(id)
  defp toggle_locked(%{id: id}), do: Reviews.admin_lock_review(id)

  defp edit_attrs(params) do
    %{
      content: trimmed(params["content"]),
      is_spoiler: params["is_spoiler"] in ["true", "on", true]
    }
  end

  defp append_sort(path, "newest"), do: path
  defp append_sort(path, sort), do: append_query(path, "sort", sort)

  defp append_query(path, key, value) do
    joiner = if String.contains?(path, "?"), do: "&", else: "?"
    path <> joiner <> "#{key}=#{value}"
  end

  defp build_title(%{review: %{is_spoiler: spoiler?}, vn: %{title: vn_title}, owner: owner}) do
    base = "'#{vn_title}' review by #{display_name(owner)} · Kaguya"
    if spoiler?, do: base, else: base
  end

  defp build_title(_), do: "Review · Kaguya"

  defp build_seo(%{review: review, vn: vn, owner: owner} = payload, base_path) do
    display_name = display_name(owner)
    title = build_title(payload)
    meta_title = "'#{vn.title}' review by #{display_name}"
    stars = rating_stars(review.rating)
    meta_description = review_meta_description(review, vn, display_name, stars)
    og_title = if stars, do: "#{stars} review of #{vn.title} by #{display_name}", else: meta_title
    canonical = @base_url <> base_path
    featured_screenshot = get_in(vn, [:featured_screenshot, :large])
    cover_image = get_in(vn, [:images, :medium])
    og_image = nonempty(featured_screenshot) || nonempty(cover_image)

    %{
      page_title: title,
      meta_description: meta_description,
      canonical_url: canonical,
      og_title: og_title,
      og_description: meta_description,
      og_url: canonical,
      og_type: "website",
      og_image: og_image,
      twitter_card: if(nonempty(featured_screenshot), do: "summary_large_image", else: "summary"),
      twitter_title: og_title,
      twitter_description: meta_description,
      twitter_image: og_image,
      json_ld: build_json_ld(payload, base_path) |> SEO.encode()
    }
  end

  defp build_json_ld(%{review: review, vn: vn, owner: owner}, base_path) do
    url = @base_url <> base_path

    %{
      "@context" => "https://schema.org",
      "@type" => "Review",
      "@id" => url,
      "url" => url,
      "datePublished" => iso8601(review.inserted_at),
      "author" => %{"@type" => "Person", "name" => display_name(owner)},
      "itemReviewed" => %{
        "@type" => "VideoGame",
        "@id" => @base_url <> "/vn/#{vn.slug}",
        "name" => vn.title,
        "url" => @base_url <> "/vn/#{vn.slug}"
      },
      "reviewBody" => strip_text(review.content)
    }
    |> maybe_put_rating(review.rating)
    |> maybe_put_image(vn)
  end

  defp maybe_put_rating(map, nil), do: map

  defp maybe_put_rating(map, rating) when is_number(rating) do
    Map.put(map, "reviewRating", %{
      "@type" => "Rating",
      "ratingValue" => Float.round(rating * 2.0, 1),
      "worstRating" => 0,
      "bestRating" => 10
    })
  end

  defp maybe_put_image(map, %{featured_screenshot: %{large: large}}) when is_binary(large),
    do: Map.put(map, "image", large)

  defp maybe_put_image(map, %{images: %{medium: medium}}) when is_binary(medium),
    do: Map.put(map, "image", medium)

  defp maybe_put_image(map, _), do: map

  defp review_meta_description(%{is_spoiler: true}, vn, display_name, stars) do
    "#{display_name}'s#{rating_phrase(stars)} review of #{vn.title}. This review contains spoilers."
  end

  defp review_meta_description(%{content: content}, _vn, _display_name, _stars)
       when is_binary(content) and content != "" do
    content
    |> strip_text()
    |> truncate_description()
  end

  defp review_meta_description(_review, vn, display_name, stars) do
    "#{display_name}'s#{rating_phrase(stars)} review of #{vn.title} on Kaguya."
  end

  defp rating_phrase(nil), do: ""
  defp rating_phrase(stars), do: " #{stars}"

  defp rating_stars(rating) when is_number(rating) and rating > 0 do
    full = floor(rating)
    half? = rating - full >= 0.5

    String.duplicate("★", full) <> if(half?, do: "½", else: "")
  end

  defp rating_stars(_), do: nil

  defp truncate_description(text) do
    if String.length(text) > 300 do
      String.slice(text, 0, 299) |> String.trim_trailing() |> then(&(&1 <> "…"))
    else
      text
    end
  end

  defp nonempty(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp nonempty(_), do: nil

  defp parse_page(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n > 0 -> n
      _ -> 1
    end
  end

  defp parse_page(_), do: 1

  defp normalize_sort(value) when is_binary(value) do
    if value in @sort_options, do: value, else: "newest"
  end

  defp normalize_sort(_), do: "newest"

  defp display_name(%{display_name: name}) when is_binary(name) and name != "", do: name
  defp display_name(%{username: username}) when is_binary(username), do: username
  defp display_name(_), do: "Kaguya user"

  defp iso8601(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp iso8601(%NaiveDateTime{} = dt),
    do: dt |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_iso8601()

  defp iso8601(_), do: nil

  defp strip_text(nil), do: ""

  defp strip_text(text) when is_binary(text) do
    text
    |> String.replace(~r/<[^>]*>/, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, 5000)
  end

  defp trimmed(value) when is_binary(value), do: String.trim(value)
  defp trimmed(_), do: ""

  defp error_message(%Ecto.Changeset{} = changeset) do
    changeset.errors
    |> Enum.map_join(", ", fn {field, {message, _}} -> "#{field} #{message}" end)
    |> case do
      "" -> "Couldn't save changes."
      msg -> msg
    end
  end

  defp error_message(:locked), do: "This review is locked."
  defp error_message(:not_found), do: "Review not found."
  defp error_message(:forbidden), do: "You don't have permission to do that."
  defp error_message(:unauthenticated), do: "Sign in to continue."
  defp error_message(message) when is_binary(message), do: message
  defp error_message(_), do: "Couldn't save changes."

  defp pluralize_comments(1), do: "Comment"
  defp pluralize_comments(_), do: "Comments"
end
