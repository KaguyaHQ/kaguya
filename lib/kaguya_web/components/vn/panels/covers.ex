defmodule KaguyaWeb.VN.Panels.Covers do
  @moduledoc """
  Covers tab: lightbox-launching grid of cover thumbnails, with the
  shared `media_like_button/1` overlay and an NSFW/suggestive blur
  applied when any of the four sensitivity flags is set.

  Blur respects the viewer's `show_nsfw_images` preference via the
  `data-nsfw-blur` contract (same mechanism as every other cover on
  the site — see `assets/css/app.css` and the inline init script in
  `root.html.heex`). No hard-coded blur-sm fallback so toggling the
  setting flips every cover instantly via the html `data-nsfw-show`
  attribute.
  """

  use KaguyaWeb, :html

  import KaguyaWeb.VN.PanelHelpers,
    only: [
      image_src: 2,
      map_value: 2,
      media_language: 1,
      media_language_label: 1,
      media_like_button: 1,
      media_year: 1
    ]

  attr :items, :list, required: true
  attr :is_logged_in, :boolean, default: false

  def panel(assigns) do
    ~H"""
    <div class="grid grid-cols-4 gap-x-1.5 gap-y-3 lg:grid-cols-6 lg:gap-x-2 lg:gap-y-5">
      <div :for={cover <- @items} class="group flex min-w-0 flex-col gap-2">
        <div class="relative transition-transform duration-200 ease-out lg:hover:scale-[1.02]">
          <button
            type="button"
            phx-click="open_media_lightbox"
            phx-value-url={image_src(cover, [:large, :medium, :small])}
            phx-value-title="Cover"
            phx-value-subtitle={cover_lightbox_label(cover)}
            class="block w-full cursor-pointer overflow-hidden rounded-md"
            title={cover_lightbox_label(cover)}
            aria-label={"Open #{cover_lightbox_label(cover)}"}
          >
            <img
              src={image_src(cover, [:medium, :small])}
              alt={cover_lightbox_label(cover)}
              data-nsfw-blur={if cover_sensitive?(cover), do: "1"}
              data-nsfw-reveal={if cover_sensitive?(cover), do: "1"}
              style={cover_blur_style(cover)}
              class="aspect-2/3 w-full rounded-md object-cover transition-[filter] duration-200 group-hover:brightness-[0.85]"
            />
          </button>
          <.media_like_button
            media={cover}
            event="toggle_cover_like"
            value_key="cover-id"
            noun="cover"
            is_logged_in={@is_logged_in}
          />
        </div>
        <p
          :if={cover_grid_label(cover)}
          class="truncate text-[11px]/4 text-[rgb(var(--foreground-tertiary))]"
        >
          {cover_grid_label(cover)}
        </p>
      </div>
    </div>
    """
  end

  def skeleton(assigns) do
    ~H"""
    <div class="grid grid-cols-4 gap-x-1.5 gap-y-3 lg:grid-cols-6 lg:gap-x-2 lg:gap-y-5">
      <div
        :for={_ <- 1..6}
        class="aspect-2/3 w-full animate-pulse rounded-md bg-[rgb(var(--surface-banner))]/40"
      >
      </div>
    </div>
    """
  end

  defp cover_lightbox_label(cover), do: cover_grid_label(cover) || "Cover"

  defp cover_grid_label(cover) do
    Enum.filter([media_language_label(media_language(cover)), media_year(cover)], & &1)
    |> Enum.join(" · ")
    |> case do
      "" -> nil
      label -> label
    end
  end

  defp cover_sensitive?(cover) do
    Enum.any?([:is_nsfw, :is_image_nsfw, :is_suggestive, :is_image_suggestive], fn key ->
      map_value(cover, key) == true
    end)
  end

  # Tiles render at ~25vw mobile / ~16vw on lg — clamp the
  # `--nsfw-blur-size` budget so small thumbnails still obscure.
  defp cover_blur_style(cover) do
    if cover_sensitive?(cover), do: "--nsfw-blur-size: 180;"
  end
end
