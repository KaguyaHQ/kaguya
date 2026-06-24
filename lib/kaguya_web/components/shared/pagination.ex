defmodule KaguyaWeb.SharedComponents.Pagination do
  @moduledoc """
  Shared pagination control.

  This component intentionally keeps URL handling server-rendered and LiveView
  friendly: centered icon previous/next controls, numbered page buttons, and
  ellipses.
  """

  use KaguyaWeb, :html

  attr :total_pages, :integer, required: true
  attr :current_page, :integer, required: true
  attr :base_path, :string, required: true
  attr :page_param, :string, default: "page"
  attr :aria_label, :string, default: "pagination"

  attr :scroll_target_id, :string,
    default: nil,
    doc: "ID of an element to scroll into view on page change. Defaults to top of window."

  attr :class, :any, default: nil

  def pagination(assigns) do
    total_pages = max(assigns.total_pages || 1, 1)
    current_page = assigns.current_page |> clamp_page(total_pages)

    assigns =
      assigns
      |> assign(:total_pages, total_pages)
      |> assign(:current_page, current_page)
      |> assign(:mobile_pages, pagination_pages(current_page, total_pages, 1))
      |> assign(:desktop_pages, pagination_pages(current_page, total_pages, 2))
      |> assign(:hook_id, nav_id(assigns.aria_label))

    ~H"""
    <nav
      :if={@total_pages > 1}
      id={@hook_id}
      phx-hook="PaginationScroll"
      role="navigation"
      aria-label={@aria_label}
      data-scroll-target-id={@scroll_target_id}
      class={["mx-auto mt-4 flex w-fit justify-center p-0", @class]}
    >
      <.pagination_list
        class="flex sm:hidden"
        pages={@mobile_pages}
        current_page={@current_page}
        total_pages={@total_pages}
        base_path={@base_path}
        page_param={@page_param}
      />
      <.pagination_list
        class="hidden sm:flex"
        pages={@desktop_pages}
        current_page={@current_page}
        total_pages={@total_pages}
        base_path={@base_path}
        page_param={@page_param}
      />
    </nav>
    """
  end

  attr :class, :any, default: nil
  attr :pages, :list, required: true
  attr :current_page, :integer, required: true
  attr :total_pages, :integer, required: true
  attr :base_path, :string, required: true
  attr :page_param, :string, required: true

  defp pagination_list(assigns) do
    ~H"""
    <ul class={["flex-row items-center gap-2", @class]}>
      <li>
        <.arrow_link
          direction={:previous}
          page={max(@current_page - 1, 1)}
          base_path={@base_path}
          page_param={@page_param}
          disabled={@current_page == 1}
        />
      </li>

      <%= for {page, idx} <- Enum.with_index(@pages) do %>
        <li :if={page == :ellipsis} key={"ellipsis-#{idx}"}>
          <span
            aria-hidden="true"
            class="flex size-8 items-center justify-center text-[rgb(var(--foreground-primary))]"
          >
            <Lucide.ellipsis class="size-4 text-[rgb(var(--foreground-tertiary))]" aria-hidden />
            <span class="sr-only">More pages</span>
          </span>
        </li>
        <li :if={page != :ellipsis} key={"page-#{page}"}>
          <.page_link
            page={page}
            current_page={@current_page}
            base_path={@base_path}
            page_param={@page_param}
          />
        </li>
      <% end %>

      <li>
        <.arrow_link
          direction={:next}
          page={min(@current_page + 1, @total_pages)}
          base_path={@base_path}
          page_param={@page_param}
          disabled={@current_page == @total_pages}
        />
      </li>
    </ul>
    """
  end

  attr :direction, :atom, required: true, values: [:previous, :next]
  attr :page, :integer, required: true
  attr :base_path, :string, required: true
  attr :page_param, :string, required: true
  attr :disabled, :boolean, default: false

  defp arrow_link(assigns) do
    assigns =
      assigns
      |> assign(
        :label,
        if(assigns.direction == :previous, do: "Go to previous page", else: "Go to next page")
      )
      |> assign(:path, page_path(assigns.base_path, assigns.page, assigns.page_param))

    ~H"""
    <span
      :if={@disabled}
      aria-label={@label}
      aria-disabled="true"
      class="inline-flex size-8 items-center justify-center rounded-[6px] bg-transparent opacity-50"
    >
      <Lucide.chevron_left :if={@direction == :previous} class="size-4" aria-hidden />
      <Lucide.chevron_right :if={@direction == :next} class="size-4" aria-hidden />
    </span>
    <.link
      :if={!@disabled}
      patch={@path}
      aria-label={@label}
      class="inline-flex size-8 items-center justify-center rounded-[6px] bg-transparent text-[rgb(var(--foreground-tertiary))] transition hover:bg-white/4 hover:text-[rgb(var(--foreground-primary))]"
    >
      <Lucide.chevron_left :if={@direction == :previous} class="size-4" aria-hidden />
      <Lucide.chevron_right :if={@direction == :next} class="size-4" aria-hidden />
    </.link>
    """
  end

  attr :page, :integer, required: true
  attr :current_page, :integer, required: true
  attr :base_path, :string, required: true
  attr :page_param, :string, required: true

  defp page_link(assigns) do
    assigns = assign(assigns, :active, assigns.page == assigns.current_page)

    ~H"""
    <.link
      patch={page_path(@base_path, @page, @page_param)}
      aria-current={if @active, do: "page"}
      class={[
        "inline-flex h-8 min-w-8 items-center justify-center rounded-[6px] border-none px-2 text-sm font-medium transition",
        @active && "bg-white/8 text-[rgb(var(--foreground-primary))] hover:bg-white/8",
        !@active &&
          "bg-transparent text-[rgb(var(--foreground-tertiary))] hover:bg-white/4 hover:text-[rgb(var(--foreground-primary))]"
      ]}
    >
      {@page}
    </.link>
    """
  end

  defp nav_id(aria_label) do
    slug =
      aria_label
      |> to_string()
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")

    "pagination-" <> if(slug == "", do: "nav", else: slug)
  end

  defp clamp_page(page, total_pages) when is_integer(page) do
    page
    |> max(1)
    |> min(total_pages)
  end

  defp clamp_page(_page, _total_pages), do: 1

  defp pagination_pages(_current_page, total_pages, _neighbors) when total_pages <= 5,
    do: Enum.to_list(1..total_pages)

  defp pagination_pages(current_page, total_pages, neighbors) do
    pages =
      MapSet.new([1, total_pages])
      |> add_range(page_window(current_page, total_pages, neighbors))
      |> MapSet.to_list()
      |> Enum.sort()

    pages
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce([hd(pages)], fn [left, right], acc ->
      if right - left > 1, do: acc ++ [:ellipsis, right], else: acc ++ [right]
    end)
  end

  defp page_window(current_page, total_pages, neighbors) do
    cond do
      current_page < 2 -> 2..min(total_pages - 1, 3)
      current_page > total_pages - 1 -> max(2, total_pages - 2)..(total_pages - 1)
      true -> max(2, current_page - neighbors)..min(total_pages - 1, current_page + neighbors)
    end
  end

  defp add_range(set, first..last//_step) when first <= last do
    Enum.reduce(first..last, set, &MapSet.put(&2, &1))
  end

  defp add_range(set, _range), do: set

  defp page_path(base_path, page, page_param) do
    [path, fragment] = split_fragment(base_path)
    path = strip_page_param(path, page_param)
    query_join = if String.contains?(path, "?"), do: "&", else: "?"

    path =
      if page <= 1 do
        path
      else
        path <> query_join <> "#{page_param}=#{page}"
      end

    path <> fragment
  end

  defp split_fragment(path) do
    case String.split(path, "#", parts: 2) do
      [path, fragment] -> [path, "##{fragment}"]
      [path] -> [path, ""]
    end
  end

  defp strip_page_param(path, page_param) do
    uri = URI.parse(path)

    query =
      (uri.query || "")
      |> URI.decode_query()
      |> Map.delete(page_param)
      |> URI.encode_query()

    base = uri.path || path

    if query == "", do: base, else: base <> "?" <> query
  end
end
