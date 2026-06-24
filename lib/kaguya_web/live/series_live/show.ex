defmodule KaguyaWeb.SeriesLive.Show do
  use KaguyaWeb, :live_view

  alias Kaguya.Authorization
  alias Kaguya.Pagination
  alias Kaguya.Series
  alias KaguyaWeb.Components.Shared.NotFoundPage

  @page_size 24

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       slug: nil,
       series: nil,
       producers: [],
       entries: [],
       pagination: empty_pagination(),
       page: 1,
       page_title: "Series",
       loading: true,
       not_found?: false
     )}
  end

  @impl true
  def handle_params(%{"slug" => slug} = params, _uri, socket) do
    page = parse_page(Map.get(params, "page"))
    opts = if can_moderate_db?(socket.assigns.current_user), do: [include_hidden: true], else: []

    case Series.get_series_by_slug(slug, opts) do
      nil ->
        {:noreply,
         assign(socket,
           slug: slug,
           page_title: "Series not found · Kaguya",
           not_found?: true,
           loading: false
         )}

      series ->
        {:ok, {entries, pagination}} =
          Series.list_vns_for_series(series, %{page: page, page_size: @page_size})

        producers = Series.list_producers_for_series(series.id)

        {:noreply,
         assign(socket,
           slug: slug,
           series: series,
           producers: producers,
           entries: entries,
           pagination: normalize_pagination(pagination),
           page: page,
           page_title: "#{series.name} (Series)",
           loading: false
         )}
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
    <main class="mx-auto mt-8 max-w-[1040px] px-4 pb-24 sm:px-6 lg:px-0">
      <div
        :if={can_moderate_db?(@current_user) && @series && @series.hidden_at}
        class="mb-4 rounded-lg border border-red-500/20 bg-red-500/10 px-4 py-2.5 text-sm text-red-400"
      >
        This entry is hidden from public view.
      </div>

      <section class="bg-surface-base border-border-divider rounded-[16px] border p-5 sm:p-6">
        <div class="flex flex-col gap-5 lg:flex-row lg:items-start lg:justify-between">
          <div class="min-w-0">
            <p class="text-xs font-medium tracking-[0.18em] text-[rgb(var(--foreground-tertiary))] uppercase">
              Series
            </p>
            <h1 class="mt-1.5 text-lg/snug font-medium text-[rgb(var(--foreground-primary))] sm:text-xl">
              {@series.name}
            </h1>

            <div class="mt-3 flex flex-wrap items-center gap-x-4 gap-y-2 text-sm text-[rgb(var(--foreground-secondary))]">
              <span>{format_count(@pagination.total_count)} visual novels</span>
              <span :if={@series.is_locked}>Locked</span>
            </div>

            <p
              :if={present?(@series.description)}
              class="text-style-body2Regular mt-3 max-w-3xl whitespace-pre-wrap text-[rgb(var(--foreground-secondary))]"
            >
              {@series.description}
            </p>
          </div>

          <div class="flex w-full shrink-0 flex-col gap-3 lg:max-w-[280px]">
            <div class="bg-surface-elevated border-border-divider rounded-[12px] border p-4">
              <p class="text-[11px] font-medium tracking-[0.16em] text-[rgb(var(--foreground-tertiary))] uppercase">
                Producers
              </p>

              <div :if={@producers == []} class="mt-3 text-sm text-[rgb(var(--foreground-secondary))]">
                No producers listed.
              </div>

              <div :if={@producers != []} class="mt-3 space-y-2">
                <div
                  :for={entry <- @producers}
                  class="flex items-center justify-between gap-3 text-sm"
                >
                  <.link
                    navigate={"/developer/#{entry.producer.slug}"}
                    class="min-w-0 truncate text-[rgb(var(--foreground-primary))] hover:text-[rgb(var(--text-link-hover))]"
                  >
                    {entry.producer.name}
                  </.link>
                  <span class="shrink-0 text-[rgb(var(--foreground-tertiary))]">
                    {labelize(entry.role || "producer")}
                  </span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      <section class="mt-6">
        <div class="flex items-center justify-between gap-4">
          <div>
            <h2 class="text-lg font-semibold text-[rgb(var(--foreground-primary))]">Entries</h2>
            <p class="mt-1 text-sm text-[rgb(var(--foreground-secondary))]">
              Ordered by series position.
            </p>
          </div>
          <span class="text-sm text-[rgb(var(--foreground-secondary))]">
            Page {@pagination.page} of {@pagination.total_pages}
          </span>
        </div>

        <div
          :if={@entries == []}
          class="bg-surface-base border-border-divider mt-6 rounded-[12px] border border-dashed p-8 text-center text-sm text-[rgb(var(--foreground-secondary))]"
        >
          No visual novels are listed for this series.
        </div>

        <div
          :if={@entries != []}
          class="mt-5 grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-6"
        >
          <article
            :for={entry <- @entries}
            class="bg-surface-base border-border-divider flex min-w-0 flex-col gap-2 rounded-[12px] border p-3"
          >
            <.link navigate={"/vn/#{entry.visual_novel.slug}"} class="block">
              <KaguyaWeb.SharedComponents.Cover.cover
                vn={entry.visual_novel}
                sizes="(min-width: 1280px) 180px, (min-width: 1024px) 22vw, (min-width: 640px) 30vw, 45vw"
                class="aspect-2/3 w-full rounded-[8px]"
                fallback_class="rounded-[8px]"
              />
            </.link>

            <div class="min-w-0">
              <p class="text-[11px] font-medium tracking-[0.16em] text-[rgb(var(--foreground-tertiary))] uppercase">
                Position {format_position(entry.position)}
              </p>
              <.link
                navigate={"/vn/#{entry.visual_novel.slug}"}
                class="mt-1 line-clamp-2 block text-sm font-medium text-[rgb(var(--foreground-primary))] hover:text-[rgb(var(--text-link-hover))]"
              >
                {entry.visual_novel.title}
              </.link>
              <p class="mt-1 text-xs text-[rgb(var(--foreground-secondary))]">
                {rating_summary(entry.visual_novel)}
              </p>
            </div>
          </article>
        </div>

        <nav
          :if={@pagination.total_pages > 1}
          class="mt-8 flex items-center justify-center gap-2"
          aria-label="Series entries pagination"
        >
          <.page_link slug={@slug} page={max(@page - 1, 1)} disabled={@page <= 1}>
            Previous
          </.page_link>
          <span class="px-2 text-sm text-[rgb(var(--foreground-secondary))]">
            Page {@page} of {@pagination.total_pages}
          </span>
          <.page_link
            slug={@slug}
            page={min(@page + 1, @pagination.total_pages)}
            disabled={@page >= @pagination.total_pages}
          >
            Next
          </.page_link>
        </nav>
      </section>
    </main>
    """
  end

  attr :slug, :string, required: true
  attr :page, :integer, required: true
  attr :disabled, :boolean, default: false
  slot :inner_block, required: true

  defp page_link(assigns) do
    ~H"""
    <%= if @disabled do %>
      <span class="border-border-divider rounded-[8px] border px-3 py-2 text-sm text-[rgb(var(--foreground-tertiary))]">
        {render_slot(@inner_block)}
      </span>
    <% else %>
      <.link
        patch={series_path(@slug, @page)}
        class="border-border-divider hover:bg-surface-elevated rounded-[8px] border px-3 py-2 text-sm text-[rgb(var(--foreground-primary))] transition-colors"
      >
        {render_slot(@inner_block)}
      </.link>
    <% end %>
    """
  end

  defp parse_page(nil), do: 1

  defp parse_page(value) do
    case Integer.parse(to_string(value)) do
      {page, _} when page > 0 -> page
      _ -> 1
    end
  end

  defp normalize_pagination(pagination) do
    total_count = Pagination.resolve_count(pagination) || 0
    total_pages = Pagination.resolve_total_pages(pagination) || 1

    %{
      page: Map.get(pagination, :page, 1),
      page_size: Map.get(pagination, :page_size, @page_size),
      total_count: total_count,
      total_pages: max(total_pages, 1)
    }
  end

  defp empty_pagination do
    %{page: 1, page_size: @page_size, total_pages: 1, total_count: 0}
  end

  defp series_path(slug, 1), do: "/series/#{slug}"
  defp series_path(slug, page), do: "/series/#{slug}?page=#{page}"

  defp present?(value) when value in [nil, ""], do: false
  defp present?(value), do: String.trim(to_string(value)) != ""

  defp can_moderate_db?(user), do: Authorization.can_moderate_db?(user)

  defp labelize(value) when is_atom(value), do: value |> Atom.to_string() |> labelize()

  defp labelize(value) when is_binary(value) do
    value
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp rating_summary(vn) do
    rating =
      case vn.average_rating do
        value when is_number(value) -> :erlang.float_to_binary(value * 1.0, decimals: 2)
        _ -> "Unrated"
      end

    votes =
      case vn.ratings_count do
        value when is_integer(value) and value > 0 -> "#{format_count(value)} ratings"
        _ -> "No ratings"
      end

    "#{rating} • #{votes}"
  end

  defp format_position(position) when is_float(position) do
    if position == Float.floor(position) do
      trunc(position)
    else
      :erlang.float_to_binary(position, decimals: 1)
    end
  end

  defp format_position(position), do: position

  defp format_count(value) when is_integer(value) do
    value
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(.{3})/, "\\1,")
    |> String.reverse()
    |> String.trim_leading(",")
  end

  defp format_count(_), do: "0"
end
