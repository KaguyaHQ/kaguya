defmodule KaguyaWeb.ProfileLive.TagVotes do
  @moduledoc """
  `/@:username/votes/tag` — cursor-paginated tag votes by the user.

  Stream 0 stub. The tag-votes agent replaces the body to mirror
  `../personal/legacy-next-app/src/components/profile/UserTagVotesList.tsx`.

  ProfileNav is hidden here too (mobile compact row only).
  """

  use KaguyaWeb.ProfileLive, tab: :tag_votes, title_suffix: "Tag votes"

  import KaguyaWeb.SharedComponents.LoadMore
  import KaguyaWeb.UI.Menu, only: [menu: 1]

  alias Kaguya.{Tags.Tag, VNTags, VisualNovels}
  alias KaguyaWeb.Components.Profile.Placeholder
  alias KaguyaWeb.SharedComponents.{Cover, Time}

  @page_size 20
  @auto_load_limit 50

  @bucket_options [
    {nil, "All"},
    {5, "Main Theme"},
    {4, "Major Element"},
    {3, "Moderate Element"},
    {2, "Lesser Element"},
    {1, "Minor Element"},
    {0, "Not relevant"}
  ]

  @sort_options [
    {:newest, "Newest"},
    {:oldest, "Oldest"}
  ]

  @impl Phoenix.LiveView
  def handle_params(%{"username" => raw_username} = params, _uri, socket) do
    username = Data.parse_username(raw_username)
    viewer = socket.assigns[:current_user]

    case Data.load_header(username, viewer) do
      {:ok, profile} ->
        sort = parse_sort(params["sort"])
        bucket = parse_bucket(params["bucket"])
        page = load_votes(profile.id, sort, bucket, nil)

        {:noreply,
         socket
         |> assign(:state, :ready)
         |> assign(:profile, profile)
         |> assign(:permissions, Data.viewer_permissions(viewer))
         |> assign(:page_title, Data.page_title(profile, "Tag votes"))
         |> assign(KaguyaWeb.SEO.noindex())
         |> assign(:sort, sort)
         |> assign(:bucket, bucket)
         |> assign(:votes, page.items)
         |> assign(:cursor, page.next_cursor)
         |> assign(:has_next, page.has_next)
         |> assign(:loading_more, false)}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> assign(:state, :not_found)
         |> assign(:page_title, "User not found · Kaguya")}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("load_more_tag_votes", _params, %{assigns: %{cursor: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_event("load_more_tag_votes", _params, %{assigns: %{has_next: false}} = socket) do
    {:noreply, socket}
  end

  def handle_event("load_more_tag_votes", _params, socket) do
    %{profile: profile, sort: sort, bucket: bucket, cursor: cursor, votes: votes} = socket.assigns

    socket = assign(socket, :loading_more, true)
    page = load_votes(profile.id, sort, bucket, cursor)

    {:noreply,
     socket
     |> assign(:votes, votes ++ page.items)
     |> assign(:cursor, page.next_cursor)
     |> assign(:has_next, page.has_next)
     |> assign(:loading_more, false)}
  end

  def handle_event(event, params, socket) when event in ["toggle_follow", "open_mod_panel"] do
    super(event, params, socket)
  end

  @impl Phoenix.LiveView
  def render(%{state: :not_found} = assigns), do: Placeholder.not_found(assigns)
  def render(%{state: :loading} = assigns), do: Placeholder.loading(assigns)

  def render(assigns) do
    assigns =
      assigns
      |> assign(:bucket_options, @bucket_options)
      |> assign(:sort_options, @sort_options)
      |> assign(:auto_load_limit, @auto_load_limit)

    ~H"""
    <main class="min-h-screen bg-[rgb(var(--surface-base))] pb-10 text-[rgb(var(--foreground-primary))] lg:px-20 lg:pb-12">
      <Header.header profile={@profile} current_tab={@current_tab} permissions={@permissions} />

      <section class="mx-auto w-full max-w-[720px] px-4 pb-10 md:px-6">
        <header class="mt-2 mb-4 flex items-end justify-between gap-4 md:mt-4 md:mb-5">
          <div>
            <h1 class="text-foreground-primary text-style-heading3Medium tracking-[-0.01em]">
              Tag votes
            </h1>
            <p class="text-foreground-tertiary text-style-captionRegular mt-0.5">
              {vote_count_label(@profile.counts.tag_votes)}
            </p>
          </div>

          <div class="flex items-center gap-1">
            <.control_menu
              id="tag-votes-bucket-menu"
              label={bucket_label(@bucket)}
              aria_label="Filter by bucket"
              active={!is_nil(@bucket)}
              options={@bucket_options}
              selected={@bucket}
              profile={@profile}
              sort={@sort}
              bucket={@bucket}
              param={:bucket}
            />
            <span aria-hidden="true" class="text-foreground-quaternary text-[11px]">·</span>
            <.control_menu
              id="tag-votes-sort-menu"
              label={sort_label(@sort)}
              aria_label="Sort order"
              active={@sort != :newest}
              options={@sort_options}
              selected={@sort}
              profile={@profile}
              sort={@sort}
              bucket={@bucket}
              param={:sort}
            />
          </div>
        </header>

        <%= cond do %>
          <% @votes == [] -> %>
            <p class="text-foreground-tertiary text-style-body2Regular mt-12 text-center">
              {empty_message(@profile.username, @profile.counts.tag_votes, @bucket)}
            </p>
          <% true -> %>
            <Cover.cover_tooltip_provider id="tag-votes-cover-tooltips">
              <ul class="divide-border-divider/30 flex flex-col divide-y">
                <.tag_vote_row :for={item <- @votes} item={item} />
              </ul>
            </Cover.cover_tooltip_provider>

            <%= cond do %>
              <% @has_next and length(@votes) < @auto_load_limit -> %>
                <div
                  id="tag-votes-auto-loader"
                  phx-hook="TagVotesAutoLoad"
                  data-loading-more={to_string(@loading_more)}
                  aria-live="polite"
                  class="text-foreground-secondary flex w-full items-center justify-center py-6 text-sm"
                >
                  Loading more tag votes
                </div>
              <% @has_next -> %>
                <div class="my-8 flex w-full items-center justify-center">
                  <.load_more
                    phx-click="load_more_tag_votes"
                    disabled={@loading_more}
                    loading_label="Loading…"
                  />
                </div>
              <% true -> %>
                <div class="h-8" />
            <% end %>
        <% end %>
      </section>
    </main>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :aria_label, :string, required: true
  attr :active, :boolean, required: true
  attr :options, :list, required: true
  attr :selected, :any, default: nil
  attr :profile, :map, required: true
  attr :sort, :atom, required: true
  attr :bucket, :integer, default: nil
  attr :param, :atom, required: true

  defp control_menu(assigns) do
    assigns =
      assign(
        assigns,
        :trigger_class,
        [
          "text-foreground-tertiary hover:text-foreground-primary inline-flex cursor-pointer items-center gap-1 rounded-[4px] px-2 py-1 text-[12px] tracking-[-0.005em] transition-colors hover:bg-white/[0.04] data-[state=open]:bg-white/[0.06] data-[state=open]:text-foreground-primary",
          assigns.active && "text-foreground-secondary"
        ]
        |> Enum.filter(& &1)
        |> Enum.join(" ")
      )

    ~H"""
    <.menu id={@id} align="end" side_offset={6} class={@trigger_class}>
      <:trigger aria-label={@aria_label}>
        <span>{@label}</span>
        <Lucide.chevron_down class="size-3 opacity-70" aria-hidden />
      </:trigger>
      <div class="bg-surface-elevated border-border-divider w-fit min-w-[132px] border p-1 shadow-[0_10px_30px_rgba(0,0,0,0.6)]">
        <.link
          :for={{value, option_label} <- @options}
          patch={option_path(@profile, @sort, @bucket, @param, value)}
          data-menu-dismiss
          class={[
            "flex w-full items-center justify-between gap-3 rounded-[5px] px-2.5 py-[7px] text-left text-[13px] leading-tight transition-colors",
            @selected == value && "bg-white/6",
            @selected != value && "hover:bg-white/4"
          ]}
        >
          <span class={[
            @selected == value && "text-foreground-primary font-medium tracking-[-0.005em]",
            @selected != value && "text-foreground-secondary"
          ]}>
            {option_label}
          </span>
          <Lucide.check
            :if={@selected == value}
            class="text-foreground-primary size-3 shrink-0"
            aria-hidden
          />
        </.link>
      </div>
    </.menu>
    """
  end

  attr :item, :map, required: true

  defp tag_vote_row(assigns) do
    ~H"""
    <li class="group flex items-center gap-4 py-3">
      <div class="w-10 shrink-0">
        <Cover.cover
          vn={@item.visual_novel}
          sizes="40px"
          link
          show_title_tooltip
          class="ring-border-divider/40 rounded-[3px] ring-1"
        />
      </div>

      <div class="flex min-w-0 flex-1 flex-col gap-1">
        <.link
          navigate={"/vn/#{@item.visual_novel.slug}"}
          class="hover:text-text-link-hover text-foreground-primary text-style-body2Medium truncate transition-colors"
        >
          {@item.visual_novel.title}
        </.link>

        <div class="text-style-captionRegular flex min-w-0 flex-wrap items-center gap-x-2 gap-y-1">
          <KaguyaWeb.SharedComponents.FilterChip.filter_chip
            label={@item.tag.display_name}
            navigate={"/browse?tags=#{@item.tag.slug}"}
            size="sm"
            tone={if @item.tag.content_warning, do: "warning", else: "neutral"}
          />
          <span class={[
            "truncate",
            @item.value == 0 && "text-foreground-quaternary",
            @item.value != 0 && "text-foreground-secondary"
          ]}>
            {bucket_label(@item.value)}
          </span>
        </div>
      </div>

      <time
        datetime={Time.datetime_title(@item.voted_at)}
        title={Time.datetime_title(@item.voted_at)}
        class="text-foreground-quaternary text-style-captionRegular shrink-0 self-start tabular-nums"
      >
        {Time.calendar_custom(@item.voted_at)}
      </time>
    </li>
    """
  end

  defp load_votes(user_id, sort, bucket, cursor) do
    order = if sort == :oldest, do: :asc, else: :desc

    {:ok, page} =
      VNTags.list_tag_votes_by_user(user_id,
        cursor: cursor,
        limit: @page_size,
        order: order,
        value: bucket
      )

    %{page | items: Enum.map(page.items, &normalize_vote/1)}
  end

  defp normalize_vote(row) do
    %{
      id: row.id,
      value: row.value,
      voted_at: row.voted_at,
      visual_novel: normalize_vn(row.visual_novel),
      tag: normalize_tag(row.tag)
    }
  end

  defp normalize_vn(vn) do
    %{
      id: vn.id,
      slug: vn.slug,
      title: vn.title,
      has_ero: vn.has_ero,
      is_image_nsfw: vn.is_image_nsfw,
      is_image_suggestive: vn.is_image_suggestive,
      images: VisualNovels.build_image_urls(vn)
    }
  end

  defp normalize_tag(tag) do
    %{
      id: tag.id,
      slug: tag.slug,
      name: tag.name,
      display_name: Tag.display_name(tag),
      content_warning: tag.content_warning == true
    }
  end

  defp parse_sort("oldest"), do: :oldest
  defp parse_sort(_), do: :newest

  defp parse_bucket(value) when value in ~w(0 1 2 3 4 5), do: String.to_integer(value)
  defp parse_bucket(_), do: nil

  defp bucket_label(nil), do: "All"
  defp bucket_label(5), do: "Main Theme"
  defp bucket_label(4), do: "Major Element"
  defp bucket_label(3), do: "Moderate Element"
  defp bucket_label(2), do: "Lesser Element"
  defp bucket_label(1), do: "Minor Element"
  defp bucket_label(0), do: "Not relevant"
  defp bucket_label(_), do: "Voted"

  defp sort_label(:oldest), do: "Oldest"
  defp sort_label(_), do: "Newest"

  defp vote_count_label(1), do: "1 vote"
  defp vote_count_label(count), do: "#{count || 0} votes"

  defp empty_message(username, 0, _bucket), do: "#{username} hasn't voted on any tags yet."
  defp empty_message(_username, _total_count, nil), do: "No tag votes to show."

  defp empty_message(_username, _total_count, bucket),
    do: "No #{String.downcase(bucket_label(bucket))} votes."

  defp option_path(profile, sort, _bucket, :bucket, value),
    do: tag_votes_path(profile, sort, value)

  defp option_path(profile, _sort, bucket, :sort, value),
    do: tag_votes_path(profile, value, bucket)

  defp tag_votes_path(profile, sort, bucket) do
    params =
      []
      |> maybe_put_param("bucket", bucket)
      |> maybe_put_param("sort", if(sort == :oldest, do: "oldest"))

    query = URI.encode_query(params)
    base = "/@#{profile.username}/votes/tag"

    if query == "", do: base, else: "#{base}?#{query}"
  end

  defp maybe_put_param(params, _key, nil), do: params
  defp maybe_put_param(params, key, value), do: [{key, to_string(value)} | params]
end
