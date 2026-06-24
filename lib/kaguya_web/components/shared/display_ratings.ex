defmodule KaguyaWeb.Components.Shared.DisplayRatings do
  @moduledoc """
  Shared read-only star renderer matching the Next.js `DisplayRatings` behavior.

  Supports:
    * half-rating text/icon mode
    * optional percentage-fill mode for fractional stars
    * optional empty-star styling in percentage-fill mode
  """

  use KaguyaWeb, :html

  attr :rating, :any, required: true
  attr :class, :any, default: nil
  attr :icon_class, :any, default: nil
  attr :star_class, :any, default: nil
  attr :empty_star_class, :any, default: nil
  attr :half_rating_class, :any, default: nil

  attr :half_rating_variant, :atom,
    default: :text,
    values: [:text, :icon]

  attr :fill_by_percentage, :boolean, default: false

  def display_ratings(assigns) do
    rating = numeric_rating(assigns.rating)
    assigns = assign(assigns, :rating_value, rating)

    ~H"""
    <span
      :if={is_number(@rating_value) and @rating_value > 0}
      class={[
        "inline-flex w-fit items-center gap-[3px] leading-none lg:translate-y-[0.85px]",
        @class
      ]}
    >
      <%= for index <- 0..4 do %>
        <.star_slot
          index={index}
          rating={@rating_value}
          icon_class={@icon_class}
          star_class={@star_class}
          empty_star_class={@empty_star_class}
          half_rating_class={@half_rating_class}
          half_rating_variant={@half_rating_variant}
          fill_by_percentage={@fill_by_percentage}
        />
      <% end %>
    </span>
    """
  end

  attr :index, :integer, required: true
  attr :rating, :float, required: true
  attr :icon_class, :any, default: nil
  attr :star_class, :any, default: nil
  attr :empty_star_class, :any, default: nil
  attr :half_rating_class, :any, default: nil
  attr :half_rating_variant, :atom, required: true
  attr :fill_by_percentage, :boolean, required: true

  defp star_slot(assigns) do
    full_star? = assigns.rating >= assigns.index + 1
    half_star? = assigns.rating >= assigns.index + 0.5

    assigns =
      assigns
      |> assign(:full_star?, full_star?)
      |> assign(:half_star?, half_star?)
      |> assign(:fractional_part, fractional_part(assigns.rating, assigns.index))
      |> assign(:fill_percent, fractional_fill_percent(assigns.rating, assigns.index))

    ~H"""
    <%= if @fill_by_percentage do %>
      <%= if @full_star? do %>
        <.star_icon class={full_star_classes(@icon_class, @star_class)} />
      <% else %>
        <%= if @fractional_part > 0 do %>
          <span class={["relative inline-block size-[13px]", @icon_class, @star_class]}>
            <.star_icon class={empty_star_classes(@icon_class, @star_class, @empty_star_class)} />
            <span
              class="absolute top-0 left-0 overflow-hidden"
              style={"width: #{@fill_percent}%"}
            >
              <.star_icon class={full_star_classes(@icon_class, @star_class)} />
            </span>
          </span>
        <% else %>
          <.star_icon class={empty_star_classes(@icon_class, @star_class, @empty_star_class)} />
        <% end %>
      <% end %>
    <% else %>
      <%= cond do %>
        <% @full_star? -> %>
          <.star_icon class={full_star_classes(@icon_class, @star_class)} />
        <% @half_star? -> %>
          <%= if @half_rating_variant == :icon do %>
            <span class={["relative inline-block size-[13px]", @icon_class, @star_class]}>
              <.star_icon class={empty_star_classes(@icon_class, @star_class, @empty_star_class)} />
              <span class="absolute top-0 left-0 w-1/2 overflow-hidden">
                <.star_icon class={full_star_classes(@icon_class, @star_class)} />
              </span>
            </span>
          <% else %>
            <span class={[
              "text-xs leading-none text-[rgb(var(--icons-user-star))]",
              @half_rating_class
            ]}>
              ½
            </span>
          <% end %>
        <% true -> %>
      <% end %>
    <% end %>
    """
  end

  attr :class, :any, default: nil

  defp star_icon(assigns) do
    ~H"""
    <svg
      viewBox="0 0 24 24"
      class={@class}
      fill="currentColor"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      <polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2" />
    </svg>
    """
  end

  defp full_star_classes(icon_class, star_class) do
    [
      "size-[13px] fill-current text-[rgb(var(--icons-user-star))]",
      icon_class,
      star_class
    ]
  end

  defp empty_star_classes(icon_class, star_class, empty_star_class) do
    [
      "size-[13px] fill-current",
      icon_class,
      star_class,
      empty_star_class || "text-[rgb(var(--icons-star-muted))]"
    ]
  end

  defp fractional_part(rating, index) do
    rating_clamped = rating |> max(0.0) |> min(5.0)
    rating_rounded = Float.round(rating_clamped, 1)
    (rating_rounded - index) |> max(0.0) |> min(1.0)
  end

  defp fractional_fill_percent(rating, index) do
    rating
    |> fractional_part(index)
    |> Kernel.*(100)
    |> round()
  end

  defp numeric_rating(value) when is_integer(value), do: value * 1.0
  defp numeric_rating(value) when is_float(value), do: value
  defp numeric_rating(_), do: nil
end
