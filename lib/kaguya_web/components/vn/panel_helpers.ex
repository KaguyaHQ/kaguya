defmodule KaguyaWeb.VN.PanelHelpers do
  @moduledoc """
  Shared helpers and small components used across the VN tab panels
  (Covers / Screenshots / Releases / Quotes / Tags). The heart-overlay
  button for covers and screenshots lives here so both panels render
  the same affordance.

  `map_value/2` papers over assigns that sometimes arrive with atom keys
  and sometimes with string keys. The proper fix is to normalise once at
  the LiveView boundary — until that happens, every renderer in this
  namespace goes through `map_value/2` instead of bare `Map.get/2`.
  """

  use KaguyaWeb, :html

  import KaguyaWeb.AuthPromptComponents, only: [show_auth_prompt: 2]
  import KaguyaWeb.VN.Formatters, only: [year: 1]

  @doc """
  Picks the first available image URL from `entity.images` matching the
  preferred sizes in order.
  """
  def image_src(entity, preferred_sizes) do
    images = Map.get(entity, :images) || Map.get(entity, "images") || %{}

    Enum.find_value(preferred_sizes, fn size ->
      Map.get(images, size) || Map.get(images, to_string(size))
    end)
  end

  def map_value(map, key) when is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  def map_value(_value, _key), do: nil

  def media_like_count(media) do
    case map_value(media, :likes_count) || map_value(media, :likesCount) do
      count when is_integer(count) -> count
      count when is_binary(count) -> String.to_integer(count)
      _ -> 0
    end
  rescue
    ArgumentError -> 0
  end

  def media_liked?(media), do: map_value(media, :liked_by_me) == true

  def media_language(media) do
    map_value(media, :language) || map_value(media, :language_code)
  end

  def media_language_label(code) when is_binary(code) and code != "" do
    code
    |> String.slice(0, 2)
    |> String.upcase()
  end

  def media_language_label(_), do: nil

  def media_year(media) do
    media
    |> map_value(:release_date)
    |> year()
  end

  @doc """
  Tailwind classes for the "Show more" `<summary>` used inside `<details>`
  blocks (releases overflow, quotes overflow).
  """
  def show_more_button_class(extra_classes) do
    List.flatten([
      "w-fit cursor-pointer list-none text-style-captionRegular text-[rgb(var(--foreground-tertiary))] transition-colors hover:text-[rgb(var(--foreground-secondary))] [&::-webkit-details-marker]:hidden",
      extra_classes
    ])
  end

  attr :media, :map, required: true
  attr :event, :string, required: true, doc: "phx-click event name."
  attr :value_key, :string, required: true, doc: "phx-value attribute suffix, e.g. \"cover-id\"."
  attr :is_logged_in, :boolean, default: false

  attr :noun, :string,
    required: true,
    doc: "Used in aria-label, e.g. \"cover\" or \"screenshot\"."

  def media_like_button(assigns) do
    assigns =
      assigns
      |> assign(:liked?, media_liked?(assigns.media))
      |> assign(:count, media_like_count(assigns.media))
      |> assign(
        :value_attrs,
        %{"phx-value-#{assigns.value_key}" => Map.get(assigns.media, :id)}
      )

    ~H"""
    <div class="pointer-events-none absolute top-1.5 right-1.5 opacity-0 transition-opacity duration-200 group-hover:pointer-events-auto group-hover:opacity-100 lg:top-2 lg:right-2">
      <button
        :if={@is_logged_in}
        id={"media-like-#{@value_key}-#{Map.get(@media, :id)}"}
        type="button"
        phx-hook="LikeButton"
        phx-click={@event}
        {@value_attrs}
        aria-label={if @liked?, do: "Unlike #{@noun}", else: "Like #{@noun}"}
        aria-pressed={if @liked?, do: "true", else: "false"}
        data-like-count-number={@count}
        class={[
          "kaguya-like-button relative flex items-center gap-1 rounded-full bg-black/50 px-2 py-1.5 text-white backdrop-blur-md transition-all duration-200 before:absolute before:-inset-2 before:content-[''] hover:scale-110 hover:bg-black/70 active:scale-95",
          @liked? && "text-[rgb(var(--like-heart))]"
        ]}
      >
        <span data-like-heart-wrap class="inline-flex">
          <Lucide.heart
            class={["kaguya-like-heart size-[13px]", @liked? && "fill-current"]}
            aria-hidden
          />
        </span>
        <span
          data-like-count-display
          class={[
            "relative inline-block h-[14px] text-[11px] leading-[14px] tabular-nums",
            @count <= 0 && "hidden"
          ]}
        >
          <span data-like-count-spacer class="invisible" aria-hidden="true">{@count}</span>
          <span data-like-count class="absolute inset-0">{@count}</span>
        </span>
      </button>

      <button
        :if={!@is_logged_in}
        id={"media-like-#{@value_key}-#{Map.get(@media, :id)}"}
        type="button"
        phx-click={show_auth_prompt("vn-auth-prompt", "Sign in to like media")}
        aria-label={"Sign in to like #{@noun}"}
        aria-pressed="false"
        class="kaguya-like-button relative flex items-center gap-1 rounded-full bg-black/50 px-2 py-1.5 text-white backdrop-blur-md transition-all duration-200 before:absolute before:-inset-2 before:content-[''] hover:scale-110 hover:bg-black/70 active:scale-95"
      >
        <span data-like-heart-wrap class="inline-flex">
          <Lucide.heart class="kaguya-like-heart size-[13px]" aria-hidden />
        </span>
        <span
          :if={@count > 0}
          class="relative inline-block h-[14px] text-[11px] leading-[14px] tabular-nums"
        >
          <span class="invisible" aria-hidden="true">{@count}</span>
          <span class="absolute inset-0">{@count}</span>
        </span>
      </button>
    </div>
    """
  end
end
