defmodule KaguyaWeb.Components.Shared.RatingsChart do
  @moduledoc """
  Shared ratings distribution chart.

  Phoenix-side port of `components/shared/RatingsChart.tsx`. Used by the
  profile overview and VN header so bar sizing, labels, footer, links, and
  tooltip treatment do not drift across surfaces.
  """

  use KaguyaWeb, :html

  import KaguyaWeb.VN.Icons, only: [display_ratings: 1]

  @ratings for i <- 1..10, do: i * 0.5

  attr :dist, :any, required: true
  attr :count, :integer, required: true
  attr :average, :float, default: 0.0
  attr :username, :string, default: nil
  attr :vn_slug, :string, default: nil
  attr :compact, :boolean, default: false
  attr :hide_title, :boolean, default: false
  attr :class, :any, default: nil
  attr :card_class, :any, default: nil
  attr :title_class, :any, default: nil
  attr :content_class, :any, default: nil

  def ratings_chart(assigns) do
    dist = normalize_dist(assigns.dist)
    max_count = max(Enum.max(dist, fn -> 0 end), 1)
    bars = build_bars(dist, max_count, assigns)
    chart_padding_class = chart_padding_class(assigns.compact, assigns.hide_title)
    chart_height_class = chart_height_class(assigns.class, assigns.card_class)

    assigns =
      assigns
      |> assign(:bars, bars)
      |> assign(:dist, dist)
      |> assign(:chart_padding_class, chart_padding_class)
      |> assign(:chart_height_class, chart_height_class)

    if assigns.count == 0 do
      ~H""
    else
      ~H"""
      <div class={[
        "relative flex flex-col p-0 shadow-none",
        @card_class,
        @count == 0 && "h-[64px] max-sm:h-[66px]"
      ]}>
        <.chart_header
          :if={!@hide_title}
          compact={@compact}
          average={@average}
          count={@count}
          title_class={@title_class}
        />

        <div class={["relative h-full grow p-0", @content_class]}>
          <%= if @compact do %>
            <.compact_chart bars={@bars} average={@average} class={@class} />
          <% else %>
            <.bar_chart
              bars={@bars}
              count={@count}
              hide_title={@hide_title}
              class={@class}
              height_class={@chart_height_class}
              padding_class={@chart_padding_class}
            />
          <% end %>
        </div>
        <.chart_footer :if={!@compact} />
      </div>
      """
    end
  end

  attr :compact, :boolean, required: true
  attr :average, :float, required: true
  attr :count, :integer, required: true
  attr :title_class, :any, default: nil

  defp chart_header(assigns) do
    ~H"""
    <div class="p-0">
      <div class="flex items-center justify-between gap-2 text-sm/4 font-normal text-[rgb(var(--foreground-primary))] md:font-medium lg:text-[10px] lg:font-light">
        <p class={[
          "text-base font-normal text-[rgb(var(--foreground-tertiary))]",
          @compact && "text-style-body1Medium text-[rgb(var(--foreground-secondary))]",
          @title_class
        ]}>
          Ratings
          <span :if={@compact} class="text-sm font-normal text-[rgb(var(--foreground-primary))]/40">
            ({@count})
          </span>
        </p>
        <div :if={!@compact} class="flex items-center gap-0.5 font-semibold">
          <.star class="-mt-px size-[11px] fill-current text-[rgb(var(--icons-star-muted))]" />
          <span class="text-xs font-semibold">{format_average(@average)}</span>
          <span class="text-xs font-light text-[rgb(var(--foreground-secondary))]">({@count})</span>
        </div>
      </div>
    </div>
    """
  end

  attr :bars, :list, required: true
  attr :average, :float, required: true
  attr :class, :any, default: nil

  defp compact_chart(assigns) do
    ~H"""
    <div class={["relative mt-2.5 h-[44px] pr-[60px] pl-[20px]", @class]}>
      <.star class="absolute -bottom-[0.5px] left-0 size-[10px] fill-current text-[rgb(var(--icons-star-muted))]" />
      <.bar_chart bars={@bars} count={0} hide_title={false} class="size-full" compact />
      <div class="absolute right-0 bottom-0 flex flex-col items-center gap-2">
        <span class="text-xl leading-none font-light text-[rgb(var(--foreground-tertiary))]">
          {format_average(@average)}
        </span>
        <div class="flex items-center">
          <.star
            :for={_ <- 1..5}
            class="size-[10px] fill-current text-[rgb(var(--icons-star-muted))]"
          />
        </div>
      </div>
    </div>
    """
  end

  attr :bars, :list, required: true
  attr :count, :integer, required: true
  attr :hide_title, :boolean, required: true
  attr :class, :any, default: nil
  attr :height_class, :any, default: nil
  attr :compact, :boolean, default: false
  attr :padding_class, :any, default: nil

  defp bar_chart(assigns) do
    ~H"""
    <div class={["aspect-auto w-full", @height_class, @padding_class, @class]}>
      <div class="grid h-full grid-cols-10 grid-rows-[1fr] items-end gap-px">
        <.bar
          :for={bar <- @bars}
          bar={bar}
          total={@count}
          compact={@compact}
          show_count_label={@hide_title}
        />
      </div>
    </div>
    """
  end

  attr :bar, :map, required: true
  attr :total, :integer, required: true
  attr :compact, :boolean, required: true
  attr :show_count_label, :boolean, required: true

  defp bar(assigns) do
    ~H"""
    <%= if @bar.href do %>
      <.link
        navigate={@bar.href}
        class="group/rating relative flex h-full flex-col justify-end focus:outline-none"
        style={rating_bar_style(@bar)}
        aria-label={rating_bucket_title(@bar.rating, @bar.users)}
      >
        <.count_label :if={@show_count_label} count={@bar.users} />
        <.bar_tooltip :if={!@bar.empty?} bar={@bar} total={@total} />
        <.bar_fill bar={@bar} compact={@compact} />
      </.link>
    <% else %>
      <span
        class="group/rating relative flex h-full flex-col justify-end"
        style={rating_bar_style(@bar)}
      >
        <.count_label :if={@show_count_label} count={@bar.users} />
        <.bar_tooltip :if={!@bar.empty?} bar={@bar} total={@total} />
        <.bar_fill bar={@bar} compact={@compact} />
      </span>
    <% end %>
    """
  end

  attr :count, :integer, required: true

  defp count_label(assigns) do
    ~H"""
    <span
      :if={@count > 0}
      class="pointer-events-none absolute left-1/2 z-20 -translate-x-1/2 text-[10px] font-medium text-[rgb(var(--foreground-secondary))] tabular-nums"
      style="bottom: calc(var(--rating-bar-height, 0%) + 7px)"
    >
      {@count}
    </span>
    """
  end

  attr :bar, :map, required: true
  attr :compact, :boolean, required: true

  defp bar_fill(assigns) do
    ~H"""
    <%= if @bar.empty? do %>
      <span class="block h-px w-full bg-white/20" />
    <% else %>
      <span
        class={[
          "block w-full bg-[rgb(var(--component-rating-distribution-bar-default))] transition-colors duration-200 group-hover/rating:bg-[rgb(var(--component-rating-distribution-bar-hover))]",
          @compact && "rounded-t-[2px]",
          !@compact && "rounded-t-[3px]"
        ]}
        style={"height: #{format_pct(@bar.height_pct)}%"}
      />
    <% end %>
    """
  end

  attr :bar, :map, required: true
  attr :total, :integer, required: true

  defp bar_tooltip(assigns) do
    ~H"""
    <span class="pointer-events-none absolute bottom-full left-1/2 z-30 mb-2 hidden -translate-x-1/2 rounded-[4px] bg-[rgb(var(--button-background-neutral-inverse-default))]/90 px-2 py-1.5 text-[rgb(var(--button-text-on-neutral-inverse))] group-focus-within/rating:block group-hover/rating:block">
      <span class="flex items-center gap-1 text-xs/4 font-semibold whitespace-nowrap">
        <span class="mt-px">{format_short(@bar.users)}</span>
        <.display_ratings
          rating={@bar.rating}
          class="gap-px"
          star_class="size-[11px] leading-none !text-[#333333]"
          half_rating_class="!text-[10px] leading-4 !text-[#333333]"
        />
        <span class="mt-px">ratings ({percentage(@bar.users, @total)}%)</span>
      </span>
    </span>
    """
  end

  defp chart_footer(assigns) do
    ~H"""
    <div class="pointer-events-none absolute inset-x-0 bottom-0 flex items-center justify-between gap-2 px-0 text-sm text-[rgb(var(--foreground-primary))]">
      <.rating_edge_label value={1} />
      <.rating_edge_label value={5} />
    </div>
    """
  end

  attr :value, :integer, required: true

  defp rating_edge_label(assigns) do
    ~H"""
    <div class="flex items-center gap-0.5 leading-none">
      <span class="text-[10px] font-medium text-[rgb(var(--foreground-tertiary))]">{@value}</span>
      <.star class="size-[10px] fill-current text-[rgb(var(--icons-star-muted))]" />
    </div>
    """
  end

  attr :class, :any, default: nil

  defp star(assigns) do
    ~H"""
    <svg viewBox="0 0 24 24" class={@class} fill="currentColor" aria-hidden="true">
      <polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2" />
    </svg>
    """
  end

  defp normalize_dist(dist) when is_list(dist) do
    dist
    |> Enum.take(10)
    |> Kernel.++(List.duplicate(0, max(10 - length(dist), 0)))
    |> Enum.map(&normalize_count/1)
  end

  defp normalize_dist(dist) when is_map(dist) do
    Enum.map(@ratings, fn rating -> bucket_count(dist, rating) end)
  end

  defp normalize_dist(_), do: List.duplicate(0, 10)

  defp bucket_count(dist, rating) do
    rating_key = :erlang.float_to_binary(rating * 1.0, decimals: 1)

    keys =
      if rating == trunc(rating) do
        int = trunc(rating)
        [rating_key, Integer.to_string(int), :"#{int}", String.to_atom(rating_key)]
      else
        [rating_key, String.to_atom(rating_key)]
      end

    Enum.reduce(keys, 0, fn key, acc -> acc + normalize_count(Map.get(dist, key)) end)
  end

  defp normalize_count(value) when is_integer(value), do: value
  defp normalize_count(value) when is_float(value), do: trunc(value)
  defp normalize_count(_), do: 0

  defp build_bars(dist, max_count, assigns) do
    @ratings
    |> Enum.with_index()
    |> Enum.map(fn {rating, idx} ->
      users = Enum.at(dist, idx, 0)

      %{
        rating: rating,
        users: users,
        height_pct: users / max_count * 100,
        empty?: users == 0,
        href: bar_href(assigns, rating)
      }
    end)
  end

  defp bar_href(%{vn_slug: slug}, rating) when is_binary(slug) and slug != "",
    do: "/vn/#{slug}/ratings/#{rating_path(rating)}"

  defp bar_href(%{username: username}, rating) when is_binary(username) and username != "",
    do: "/@#{username}/library?rating=#{rating_path(rating)}"

  defp bar_href(_, _), do: nil

  defp rating_path(rating) when rating == trunc(rating), do: Integer.to_string(trunc(rating))
  defp rating_path(rating), do: :erlang.float_to_binary(rating * 1.0, decimals: 1)

  defp format_pct(pct) when is_number(pct), do: :erlang.float_to_binary(pct * 1.0, decimals: 2)

  defp format_average(value) when is_number(value),
    do: :erlang.float_to_binary(value * 1.0, decimals: 1)

  defp format_average(_), do: "0.0"

  defp chart_padding_class(true, _hide_title), do: nil
  defp chart_padding_class(false, true), do: "pt-[20px] pb-[18px]"
  defp chart_padding_class(false, false), do: "pt-[12px] pb-[18px]"

  defp chart_height_class(class, _card_class) when not is_nil(class), do: nil
  defp chart_height_class(_class, card_class) when not is_nil(card_class), do: "h-full"
  defp chart_height_class(_class, _card_class), do: "h-[100px]"

  defp rating_bar_style(bar), do: "--rating-bar-height: #{format_pct(bar.height_pct)}%"

  defp rating_bucket_title(rating, count),
    do: "#{rating_path(rating)} stars: #{format_short(count)}"

  defp percentage(_count, 0), do: "0"
  defp percentage(count, total), do: Integer.to_string(round(count / total * 100))

  defp format_short(nil), do: "0"

  defp format_short(value) when is_integer(value) do
    cond do
      value >= 1_000_000 -> trim_decimal(value / 1_000_000) <> "M"
      value >= 1_000 -> trim_decimal(value / 1_000) <> "K"
      true -> Integer.to_string(value)
    end
  end

  defp trim_decimal(value) do
    formatted = :erlang.float_to_binary(value * 1.0, decimals: 1)
    if String.ends_with?(formatted, ".0"), do: String.slice(formatted, 0..-3//1), else: formatted
  end
end
