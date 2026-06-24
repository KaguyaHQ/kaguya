defmodule KaguyaWeb.SharedComponents.LikeButton do
  @moduledoc """
  Shared Phoenix port of production's `LikeButton`.

  This component owns only the visual and event-contract surface. The parent
  LiveView or LiveComponent still owns auth, persistence, and optimistic state.
  """

  use KaguyaWeb, :html

  attr :id, :string, required: true
  attr :liked, :boolean, default: false
  attr :likes_count, :integer, default: 0
  attr :click, :string, default: "toggle_like"
  attr :target, :any, default: nil
  attr :value_id, :string, default: nil
  attr :value_review_id, :string, default: nil
  attr :value_liked, :boolean, default: nil
  attr :size, :atom, default: :default, values: [:default, :sm]
  attr :hide_count, :boolean, default: false
  attr :class, :any, default: nil
  attr :text_class, :any, default: nil
  attr :icon_container_class, :any, default: nil
  attr :icon_class, :any, default: nil

  def like_button(assigns) do
    assigns =
      assigns
      |> assign(:size_classes, size_classes(assigns.size))
      |> assign(:display_count?, !assigns.hide_count and (assigns.likes_count || 0) > 0)
      |> assign(:formatted_count, format_count(assigns.likes_count || 0))
      |> assign(:heart_class, heart_class(assigns))

    ~H"""
    <button
      id={@id}
      type="button"
      phx-hook="LikeButton"
      phx-click={@click}
      phx-target={@target}
      phx-value-id={@value_id}
      phx-value-review-id={@value_review_id}
      phx-value-liked={unless is_nil(@value_liked), do: to_string(@value_liked)}
      aria-pressed={to_string(@liked)}
      aria-label={if @liked, do: "Unlike", else: "Like"}
      data-like-count-number={@likes_count || 0}
      class={[
        "group kaguya-like-button relative inline-flex items-center rounded-full before:absolute before:content-['']",
        @size_classes.button,
        @class
      ]}
    >
      <span class="sr-only">
        {if @liked, do: "Unlike", else: "Like"} ({@likes_count || 0})
      </span>
      <span class={[
        "flex items-center rounded-full",
        if(@hide_count, do: "gap-0", else: "-space-x-0.5")
      ]}>
        <span
          data-like-heart-wrap
          class={[
            "kaguya-like-heart-wrap flex items-center justify-center rounded-full lg:group-hover:bg-white/4",
            @size_classes.container,
            @icon_container_class
          ]}
        >
          <Lucide.heart
            class={@heart_class}
            aria-hidden
          />
        </span>

        <span
          :if={!@hide_count}
          data-like-count-display
          class={[
            "relative inline-block translate-y-[0.5px] lg:translate-y-px",
            @size_classes.count,
            !@display_count? && "hidden"
          ]}
        >
          <span data-like-count-spacer class={["invisible", @text_class]} aria-hidden="true">
            {@formatted_count}
          </span>
          <span
            data-like-count
            class={[
              "absolute inset-0 font-normal text-[rgb(var(--foreground-secondary))] transition-colors lg:group-hover:text-[rgb(var(--like-heart))]",
              @size_classes.count_text,
              @text_class,
              @liked && "text-[rgb(var(--like-heart))]"
            ]}
          >
            {@formatted_count}
          </span>
        </span>
      </span>
    </button>
    """
  end

  defp size_classes(:sm) do
    %{
      button: "before:-inset-2",
      container: "size-7",
      icon: "h-4 w-4",
      count: "h-4 text-xs",
      count_text: "text-xs"
    }
  end

  defp size_classes(_size) do
    %{
      button: "before:-inset-1.5",
      container: "size-8",
      icon: "h-[18px] w-[18px]",
      count: "h-5 text-sm",
      count_text: "text-sm"
    }
  end

  defp heart_class(assigns) do
    [
      "kaguya-like-heart text-[rgb(var(--foreground-secondary))] transition-colors duration-100 lg:group-hover:fill-[rgb(var(--like-heart))] lg:group-hover:text-[rgb(var(--like-heart))]",
      size_classes(assigns.size).icon,
      assigns.icon_class,
      assigns.liked && "fill-[rgb(var(--like-heart))] text-[rgb(var(--like-heart))]"
    ]
    |> Enum.reject(&(&1 in [nil, false, true, ""]))
    |> Enum.join(" ")
  end

  defp format_count(value) when is_integer(value) and value >= 1_000_000 do
    "#{Float.round(value / 1_000_000, 1)}M"
  end

  defp format_count(value) when is_integer(value) and value >= 1_000 do
    "#{Float.round(value / 1_000, 1)}K"
  end

  defp format_count(value), do: to_string(value || 0)
end
