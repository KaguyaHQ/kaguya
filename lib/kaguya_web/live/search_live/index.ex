defmodule KaguyaWeb.SearchLive.Index do
  use KaguyaWeb, :live_view

  alias Kaguya.{Lists, Pagination, Repo, Series, VisualNovels}
  alias KaguyaWeb.SharedComponents.Cover

  @page_size 24
  @types ~w(visualNovels series characters lists)
  @type_labels %{
    "visualNovels" => "Visual Novels",
    "series" => "Series",
    "characters" => "Characters",
    "lists" => "Lists"
  }

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Search • Kaguya")
     |> assign(:meta_description, "Search")
     |> assign(KaguyaWeb.SEO.noindex())
     |> assign(:types, @types)
     |> assign(:type_labels, @type_labels)}
  end

  def handle_params(params, _uri, socket) do
    query = params |> Map.get("q", "") |> String.trim()
    type = normalize_type(Map.get(params, "type"))
    page = parse_page(Map.get(params, "page"))

    {:noreply,
     socket
     |> assign(:query, query)
     |> assign(:type, type)
     |> assign(:page, page)
     |> assign(:placeholder, placeholder(type))
     |> load_results()}
  end

  def render(assigns) do
    ~H"""
    <div class="mx-[calc(50%-50vw)] min-h-screen w-screen pt-8 pb-[110px] sm:pt-10 sm:pb-32">
      <div class="mx-auto flex max-w-[1092px] scroll-mt-24 flex-col rounded-[12px] max-md:px-4 md:p-8 md:pt-6 md:max-lg:px-8">
        <div class="flex items-start justify-between gap-3">
          <form
            id="search-page-form"
            action="/search"
            method="get"
            phx-hook="LvNavGetForm"
            class="flex items-center max-sm:w-full"
          >
            <input type="hidden" name="type" value={@type} />
            <div class="relative max-sm:w-full max-sm:flex-1">
              <.search_icon
                class="text-foreground-primary pointer-events-none absolute top-1/2 left-4 size-5 -translate-y-1/2 sm:left-3 sm:size-4"
                aria-hidden
              />
              <input
                type="search"
                name="q"
                value={@query}
                placeholder={"Search #{@placeholder}"}
                class="bg-surface-elevated border-text-field-border focus:border-text-field-border-focus placeholder:text-foreground-primary/40 text-foreground-primary h-11 rounded-l-[8px] rounded-r-none border pl-12 text-sm font-normal focus:outline-none max-sm:w-full max-sm:flex-1 max-sm:rounded-[100px] sm:w-[284px] sm:pl-9 lg:w-[345px]"
              />
            </div>
            <button
              type="submit"
              class="bg-button-background-brand-default hover:bg-button-background-brand-hover text-button-text-on-brand h-[44px] w-fit rounded-l-none rounded-r-[8px] px-9 py-3 text-sm font-medium transition max-sm:hidden"
            >
              Search
            </button>
          </form>
        </div>

        <div class="border-b-border-divider text-foreground-primary mt-6 mb-0 flex items-center justify-between gap-4 border-b max-sm:flex-col max-sm:items-start max-sm:gap-2">
          <nav class="mb-[-3px] flex w-full overflow-x-auto bg-transparent p-0 [scrollbar-width:none] max-sm:gap-2 max-sm:pr-4 sm:space-x-6 [&::-webkit-scrollbar]:hidden">
            <.link
              :for={type <- @types}
              patch={tab_path(type, @query)}
              class={[
                "text-foreground-primary border-b-2 border-b-transparent px-3 py-2 text-sm font-semibold sm:px-[17px] sm:text-base",
                @type == type && "border-b-button-background-brand-default"
              ]}
            >
              {@type_labels[type]}
            </.link>
          </nav>
          <div class="flex items-center gap-3">
            <span class="leading-[22px] font-light text-[#adadad] max-sm:text-sm">
              ({format_count(@total_count)} results)
            </span>
          </div>
        </div>

        <div :if={@error} class="mt-4 flex items-center text-red-400">
          <Lucide.triangle_alert class="mr-2 size-5" aria-hidden />
          Something went wrong. Please try again.
        </div>

        <div :if={!@error && @query != "" && @items == []} class="text-foreground-primary/80 mt-4">
          No results found for your search.
        </div>

        <div class="mt-5 gap-4 md:mt-10">
          <.vn_results :if={@type == "visualNovels"} items={@items} />
          <.series_results :if={@type == "series"} items={@items} />
          <.character_results :if={@type == "characters"} items={@items} />
          <.list_results :if={@type == "lists"} items={@items} />

          <.pagination_controls
            :if={!@error && @total_pages && @total_pages > 1}
            page={@page}
            total_pages={@total_pages}
            type={@type}
            query={@query}
          />
        </div>
      </div>
    </div>
    """
  end

  defp load_results(socket) do
    type = socket.assigns.type
    query = socket.assigns.query
    page = socket.assigns.page

    case search(type, query, page, socket.assigns.current_user) do
      {:ok, %{items: items, pagination: pagination}} ->
        total_count = total_count(pagination)
        total_pages = total_pages(pagination)

        assign(socket,
          items: items,
          pagination: pagination,
          total_count: total_count,
          total_pages: total_pages,
          error: false
        )

      {:ok, %{items: items, next_cursor: next_cursor, has_next: has_next}} ->
        assign(socket,
          items: preload_lists(items),
          pagination: nil,
          total_count: length(items),
          total_pages: if(has_next || next_cursor, do: page + 1, else: page),
          error: false
        )

      {:error, _reason} ->
        assign(socket,
          items: [],
          pagination: nil,
          total_count: 0,
          total_pages: 1,
          error: true
        )
    end
  end

  defp search("visualNovels", query, page, current_user) do
    opts = [
      include_nukige: Map.get(current_user || %{}, :show_nukige, true),
      include_adjacent: Map.get(current_user || %{}, :show_adjacent, true)
    ]

    VisualNovels.search_visual_novels(query, page, @page_size, opts)
  end

  defp search("characters", query, page, _current_user) do
    VisualNovels.search_characters(query, page, @page_size)
  end

  defp search("series", query, page, _current_user) do
    {:ok, Series.search_series(query, page: page, page_size: @page_size)}
  end

  defp search("lists", "", page, current_user) do
    viewer_id = Map.get(current_user || %{}, :id)

    Lists.list_trending_lists_for_viewer(viewer_id, nil, @page_size)
    |> case do
      {:ok, result} -> {:ok, %{result | items: preload_lists(result.items)}}
      other -> other
    end
    |> maybe_limit_trending_page(page)
  end

  defp search("lists", query, page, current_user) do
    viewer_id = Map.get(current_user || %{}, :id)

    case Lists.search_lists(query, page, @page_size, viewer_id) do
      {:ok, %{items: items} = result} -> {:ok, %{result | items: preload_lists(items)}}
      other -> other
    end
  end

  defp maybe_limit_trending_page({:ok, result}, 1), do: {:ok, result}
  defp maybe_limit_trending_page({:ok, result}, _page), do: {:ok, %{result | items: []}}
  defp maybe_limit_trending_page(other, _page), do: other

  defp preload_lists(items) do
    Repo.preload(items, [:user, :visual_novels])
  end

  defp total_count(%{total_count: count}) when is_integer(count), do: count
  defp total_count(%{_count_query: _} = pagination), do: Pagination.resolve_count(pagination)
  defp total_count(_), do: 0

  defp total_pages(%{total_pages: pages}) when is_integer(pages), do: pages

  defp total_pages(%{_count_query: _} = pagination),
    do: Pagination.resolve_total_pages(pagination)

  defp total_pages(_), do: 1

  defp normalize_type(type) when type in @types, do: type
  defp normalize_type(_), do: "visualNovels"

  defp parse_page(page) when is_binary(page) do
    case Integer.parse(page) do
      {n, ""} when n > 0 -> n
      _ -> 1
    end
  end

  defp parse_page(_), do: 1

  defp placeholder("visualNovels"), do: "by title"
  defp placeholder("characters"), do: "by name"
  defp placeholder("series"), do: "by name"
  defp placeholder("lists"), do: "by name"
  defp placeholder(_), do: "by title"

  defp tab_path(type, ""), do: ~p"/search?type=#{type}"
  defp tab_path(type, query), do: ~p"/search?type=#{type}&q=#{query}"

  defp page_path(type, query, page) when page <= 1, do: tab_path(type, query)
  defp page_path(type, "", page), do: ~p"/search?type=#{type}&page=#{page}"
  defp page_path(type, query, page), do: ~p"/search?type=#{type}&q=#{query}&page=#{page}"

  defp format_count(count) when is_integer(count), do: count |> Integer.to_string() |> delimit()
  defp format_count(_), do: "0"

  defp delimit(value) do
    value
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.map_join(",", &Enum.join/1)
    |> String.reverse()
  end

  attr :items, :list, required: true

  defp vn_results(assigns) do
    ~H"""
    <div class="flex flex-col gap-4 px-0 pb-5 sm:grid sm:grid-cols-4 sm:gap-4 sm:pb-10 md:grid-cols-5 md:gap-y-6 lg:grid-cols-6">
      <.link :for={vn <- @items} navigate={"/vn/#{vn.slug}"} class="block">
        <div class="flex items-center gap-4 sm:flex-col sm:items-stretch sm:gap-2">
          <div class="bg-surface-elevated flex h-[72px] w-12 shrink-0 overflow-hidden rounded-[4px] shadow-[0px_4px_10px_rgba(0,0,0,0.35)] sm:aspect-1/1.5 sm:h-auto sm:w-full">
            <Cover.cover
              vn={search_result_cover_vn(vn)}
              sizes="(max-width: 640px) 48px, (max-width: 1024px) 20vw, 168px"
              class="rounded-[4px]"
              fallback_class="rounded-[4px]"
            />
          </div>
          <div class="sm:bg-surface-base flex flex-col gap-2 sm:justify-center sm:rounded-b-[4px]">
            <span class="font-source-serif lg:hover:text-text-link-hover text-foreground-primary line-clamp-2 leading-[22px] font-semibold sm:text-sm">
              {vn.title}
            </span>
            <p class="text-foreground-secondary line-clamp-1 text-sm font-medium sm:text-xs sm:font-normal">
              {Map.get(vn, :producers)}
            </p>
          </div>
        </div>
      </.link>
    </div>
    """
  end

  attr :items, :list, required: true

  defp series_results(assigns) do
    ~H"""
    <div class="grid grid-cols-2 gap-x-3 gap-y-5 sm:grid-cols-3 sm:gap-x-3.5 sm:gap-y-6 lg:grid-cols-6 lg:gap-x-3 lg:gap-y-6">
      <.link :for={series <- @items} navigate={"/series/#{series.slug}"} class="block">
        <div class="group text-foreground-primary flex flex-col">
          <.cover_img
            src={Map.get(series, :primary_image_url)}
            alt={series.name}
            class="aspect-1/1.5 w-full rounded-[6px] object-cover object-center"
            blur_nsfw={Map.get(series, :root_cover_needs_blur) == true}
            nsfw_blur_size="180"
          />
          <div class="mt-2 flex flex-1 flex-col gap-1.5">
            <p class="line-clamp-2 text-[13px] leading-[18px] font-medium sm:text-sm/5">
              {series.name}
            </p>
            <p
              :if={producer_line(series)}
              class="text-foreground-secondary line-clamp-2 text-[11px]/4 sm:line-clamp-1"
            >
              {producer_line(series)}
            </p>
            <div class="text-foreground-tertiary mt-auto flex items-center text-[11px]/4">
              <span>
                {entry_count(series)} {if entry_count(series) == 1, do: "title", else: "titles"}
              </span>
            </div>
          </div>
        </div>
      </.link>
    </div>
    """
  end

  attr :items, :list, required: true

  defp character_results(assigns) do
    ~H"""
    <div class="grid grid-cols-3 gap-x-[11px] gap-y-4 px-0 pb-5 sm:grid-cols-4 sm:pb-10 lg:grid-cols-6 lg:gap-x-[30px] lg:gap-y-8">
      <.link
        :for={character <- @items}
        navigate={"/character/#{character.slug}"}
        class="flex flex-col items-center justify-start gap-2"
      >
        <KaguyaWeb.SharedComponents.CharacterImage.character_image
          character={character}
          sizes="(max-width: 640px) 106px, (max-width: 768px) 140px, 155px"
          class="size-[106px] object-cover object-center sm:size-[140px] md:size-[155px]"
          fallback_class="size-[106px] sm:size-[140px] md:size-[155px] bg-[rgb(var(--surface-elevated))]"
          rounded="rounded-[4px]"
        />
        <span class="text-foreground-primary line-clamp-2 w-full text-center text-sm leading-[17px] font-semibold lg:text-base lg:leading-[19px]">
          {character.name}
        </span>
      </.link>
    </div>
    """
  end

  attr :items, :list, required: true

  defp list_results(assigns) do
    ~H"""
    <div class="grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
      <.link :for={list <- @items} navigate={list_href(list)} class="block">
        <div class="overflow-hidden rounded-[4px]">
          <KaguyaWeb.SharedComponents.StackedCovers.stacked_covers
            items={Enum.take(list_visual_novels(list), 5)}
            sizes="80px"
            max_covers={5}
            container_class="flex w-full overflow-hidden rounded-[4px] -space-x-[36px] sm:-space-x-[20px] bg-transparent"
            item_class="!flex-none w-[30%] rounded-[4px] shadow-[0_4px_10px_rgba(0,0,0,0.35)]"
            image_class="rounded-[4px]"
            empty_slot_class="bg-surface-elevated"
          />
          <h3 class="font-source-serif text-foreground-primary mt-2 line-clamp-2 text-base font-semibold">
            {list.name}
          </h3>
          <p class="text-foreground-secondary mt-1 text-sm">
            by {get_in(list, [Access.key(:user), Access.key(:username)]) || "Kaguya user"} • {list.vns_count ||
              0} VNs
          </p>
        </div>
      </.link>
    </div>
    """
  end

  attr :src, :string, default: nil
  attr :alt, :string, default: ""
  attr :class, :string, required: true
  attr :blur_nsfw, :boolean, default: false
  attr :nsfw_blur_size, :string, default: "100"

  defp cover_img(assigns) do
    ~H"""
    <%= if @src do %>
      <img
        src={@src}
        alt={@alt}
        class={@class}
        loading="lazy"
        data-nsfw-blur={if @blur_nsfw, do: "1"}
        style={if @blur_nsfw, do: "--nsfw-blur-size: #{@nsfw_blur_size};"}
      />
    <% else %>
      <div class={[
        @class,
        "bg-surface-elevated text-foreground-secondary flex items-center justify-center text-[10px]"
      ]}>
        No Image
      </div>
    <% end %>
    """
  end

  attr :page, :integer, required: true
  attr :total_pages, :integer, required: true
  attr :type, :string, required: true
  attr :query, :string, required: true

  defp pagination_controls(assigns) do
    ~H"""
    <nav class="my-6 flex w-full items-center justify-center gap-3 text-sm">
      <.link
        :if={@page > 1}
        patch={page_path(@type, @query, @page - 1)}
        class="bg-button-background-neutral-default text-foreground-primary rounded-[8px] px-4 py-2 font-medium"
      >
        Previous
      </.link>
      <span class="text-foreground-secondary">Page {@page} of {@total_pages}</span>
      <.link
        :if={@page < @total_pages}
        patch={page_path(@type, @query, @page + 1)}
        class="bg-button-background-neutral-default text-foreground-primary rounded-[8px] px-4 py-2 font-medium"
      >
        Next
      </.link>
    </nav>
    """
  end

  defp producer_line(series) do
    series
    |> Map.get(:series_producers, [])
    |> Enum.map(&get_in(&1, [Access.key(:producer), Access.key(:name)]))
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
    |> case do
      "" -> nil
      line -> line
    end
  end

  defp entry_count(series), do: Map.get(series, :entry_count) || 0

  defp list_visual_novels(list) do
    case Map.get(list, :visual_novels) do
      %Ecto.Association.NotLoaded{} -> []
      vns when is_list(vns) -> vns
      _ -> []
    end
  end

  defp list_href(%{user: %{username: username}, slug: slug}) when is_binary(username) do
    "/@#{username}/list/#{slug}"
  end

  defp list_href(%{slug: slug}), do: "/lists/#{slug}"

  defp search_result_cover_vn(vn) do
    cover_sensitive = bool(Map.get(vn, :has_ero) || Map.get(vn, "has_ero"))
    nsfw = bool(Map.get(vn, :is_image_nsfw) || Map.get(vn, "is_image_nsfw"))
    suggestive = bool(Map.get(vn, :is_image_suggestive) || Map.get(vn, "is_image_suggestive"))

    %{
      title: Map.get(vn, :title) || Map.get(vn, "title"),
      slug: Map.get(vn, :slug) || Map.get(vn, "slug"),
      image_url: Map.get(vn, :image_url) || Map.get(vn, "image_url"),
      images: Map.get(vn, :images) || Map.get(vn, "images") || %{},
      is_image_nsfw: nsfw || cover_sensitive,
      is_image_suggestive: suggestive
    }
  end

  defp bool(true), do: true
  defp bool(_), do: false
end
