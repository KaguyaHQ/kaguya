defmodule KaguyaWeb.SharedComponents.Cover do
  @moduledoc """
  Shared VN cover component — Phoenix-side port of
  `../personal/legacy-next-app/src/components/shared/Cover.tsx`.

  One reusable HEEx component that handles:

    * `<img srcset>` with the 128/256/512/1024 w breakpoints used across
      the app.
    * Optional `<a>` wrapper to `/vn/:slug` (set `link={true}`).
    * Optional title tooltip via the `data-cover-title` attribute, wired
      up by `cover_tooltip_provider/1` which mounts the `CoverTooltip`
      JS hook.
    * Optional graceful fallback when no image is available (title in a
      muted card matching prod's `CoverFallback`).
    * Letterboxd-style drop shadow (`shadow={true}`).
    * Production-compatible NSFW cover blur via `data-nsfw-blur` when
      the cover image itself is marked NSFW/suggestive.

  The more involved parts of prod's `Cover.tsx` — dialog zoom,
  cover-edit mode, and intersection-observer-driven lazy loading — are
  intentionally deferred. They depend on context providers and Radix
  dialogs that aren't ported yet.

  ## Examples

      <%!-- Plain image, no link --%>
      <Cover.cover vn={@vn} sizes="180px" class="w-full rounded-[8px]" eager />

      <%!-- Cover that opens the VN page, with tooltip + drop shadow --%>
      <Cover.cover_tooltip_provider>
        <:children>
          <Cover.cover vn={@vn} sizes="106px" link show_title_tooltip shadow class="w-full rounded-[2px]" />
        </:children>
      </Cover.cover_tooltip_provider>
  """

  use KaguyaWeb, :html

  alias Kaguya.VisualNovels

  @cover_shadow "box-shadow: 0px 4px 10px rgba(0, 0, 0, 0.35);"

  # ---------------------------------------------------------------------------
  # Cover image
  # ---------------------------------------------------------------------------

  attr :vn, :map,
    required: true,
    doc: "Map with `:images` (`%{small/medium/large/xl}`), `:slug`, `:title`."

  attr :sizes, :string, required: true, doc: "HTML `sizes` attribute for `srcset`."
  attr :class, :any, default: nil, doc: "Class for the image element."
  attr :fallback_class, :any, default: nil, doc: "Class for the no-image fallback card."
  attr :eager, :boolean, default: false, doc: "Use `loading=eager` and `fetchpriority=high`."
  attr :link, :boolean, default: false, doc: "Wrap in a link to `/vn/:slug`."

  attr :show_title_tooltip, :boolean,
    default: false,
    doc: "Stamps `data-cover-title` for the tooltip hook to pick up."

  attr :shadow, :boolean, default: false, doc: "Apply the Letterboxd-style drop shadow."
  attr :style, :string, default: nil, doc: "Extra inline style (merged with `shadow`)."
  attr :object_fit, :string, default: "cover", values: ["cover", "contain"]
  attr :alt, :string, default: nil, doc: "Override the alt text (defaults to the VN title)."

  attr :blur_nsfw, :boolean,
    default: true,
    doc: "Apply production NSFW blur when the cover image is NSFW/suggestive."

  attr :enable_nsfw_reveal, :boolean,
    default: false,
    doc: "Allow the first click on a blurred NSFW/suggestive cover to reveal it."

  attr :rest, :global

  def cover(assigns) do
    assigns =
      assigns
      |> assign(:has_image, has_image?(assigns.vn))
      |> assign(:adult_cover, adult_cover?(assigns.vn))
      |> assign(:image_src, image_src(assigns.vn))
      |> assign(:image_srcset, image_srcset(assigns.vn))
      |> assign(:nsfw_blur_size, nsfw_blur_size(assigns.sizes))
      |> assign(:alt, assigns.alt || (assigns.vn && Map.get(assigns.vn, :title)) || "Cover")

    ~H"""
    <%= if @link and href_for(@vn) do %>
      <.link
        navigate={href_for(@vn)}
        title={native_title(@show_title_tooltip, @vn)}
        data-cover-title={tooltip_title(@show_title_tooltip, @vn)}
        class="block size-full"
      >
        <.cover_body
          vn={@vn}
          has_image={@has_image}
          adult_cover={@adult_cover}
          image_src={@image_src}
          image_srcset={@image_srcset}
          sizes={@sizes}
          class={@class}
          fallback_class={@fallback_class}
          eager={@eager}
          shadow={@shadow}
          style={@style}
          object_fit={@object_fit}
          alt={@alt}
          blur_nsfw={@blur_nsfw}
          enable_nsfw_reveal={@enable_nsfw_reveal}
          nsfw_blur_size={@nsfw_blur_size}
        />
      </.link>
    <% else %>
      <span data-cover-title={tooltip_title(@show_title_tooltip, @vn)} class="block size-full">
        <.cover_body
          vn={@vn}
          has_image={@has_image}
          adult_cover={@adult_cover}
          image_src={@image_src}
          image_srcset={@image_srcset}
          sizes={@sizes}
          class={@class}
          fallback_class={@fallback_class}
          eager={@eager}
          shadow={@shadow}
          style={@style}
          object_fit={@object_fit}
          alt={@alt}
          blur_nsfw={@blur_nsfw}
          enable_nsfw_reveal={@enable_nsfw_reveal}
          nsfw_blur_size={@nsfw_blur_size}
        />
      </span>
    <% end %>
    """
  end

  attr :vn, :map, required: true
  attr :has_image, :boolean, required: true
  attr :adult_cover, :boolean, required: true
  attr :image_src, :string, default: nil
  attr :image_srcset, :string, default: nil
  attr :sizes, :string, required: true
  attr :class, :string, default: nil
  attr :fallback_class, :string, default: nil
  attr :eager, :boolean, required: true
  attr :shadow, :boolean, required: true
  attr :style, :string, default: nil
  attr :object_fit, :string, required: true
  attr :alt, :string, required: true
  attr :blur_nsfw, :boolean, required: true
  attr :enable_nsfw_reveal, :boolean, required: true
  attr :nsfw_blur_size, :string, required: true

  defp cover_body(assigns) do
    ~H"""
    <%= if @has_image do %>
      <img
        src={@image_src}
        srcset={@image_srcset}
        sizes={@sizes}
        alt={@alt}
        loading={if @eager, do: "eager", else: "lazy"}
        fetchpriority={if @eager, do: "high"}
        decoding="async"
        draggable="false"
        data-nsfw-blur={if @adult_cover and @blur_nsfw, do: "1"}
        data-nsfw-reveal={if @adult_cover and @blur_nsfw and @enable_nsfw_reveal, do: "1"}
        style={merge_styles(@shadow, @style, @adult_cover and @blur_nsfw, @nsfw_blur_size)}
        class={[
          "size-full object-center text-transparent transition-opacity duration-300",
          if(@object_fit == "contain", do: "object-contain", else: "object-cover"),
          @class
        ]}
      />
    <% else %>
      <div class={[
        "bg-surface-elevated text-foreground-tertiary flex aspect-2/3 items-center justify-center p-2 text-center text-xs",
        @fallback_class,
        @class
      ]}>
        <span class="line-clamp-3">{@vn && Map.get(@vn, :title)}</span>
      </div>
    <% end %>
    """
  end

  # ---------------------------------------------------------------------------
  # Tooltip provider — wraps a group of covers, mounts the JS hook that
  # owns the floating tooltip element.
  # ---------------------------------------------------------------------------

  attr :id, :string, default: "cover-tooltip-root"
  attr :delay, :integer, default: 650, doc: "Delay before showing the tooltip (ms)."
  attr :skip_delay, :integer, default: 1000, doc: "Warmth window after a hide (ms)."
  attr :data_attribute, :string, default: "data-cover-title"
  attr :class, :any, default: nil
  attr :style, :string, default: nil
  slot :inner_block, required: true

  def cover_tooltip_provider(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="CoverTooltip"
      data-delay-duration={@delay}
      data-skip-delay-duration={@skip_delay}
      data-tooltip-attribute={@data_attribute}
      class={@class}
      style={@style}
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp has_image?(nil), do: false

  defp has_image?(vn) do
    images = images_for(vn)

    Map.get(images, :small) || Map.get(images, :medium) || Map.get(images, :large) ||
      Map.get(images, :xl) || Map.get(vn, :image_url)
  end

  defp adult_cover?(nil), do: false

  defp adult_cover?(vn) do
    [
      :is_image_nsfw,
      :is_image_suggestive,
      "is_image_nsfw",
      "is_image_suggestive"
    ]
    |> Enum.any?(&(Map.get(vn, &1) == true))
  end

  defp image_src(nil), do: nil

  defp image_src(vn) do
    images = images_for(vn)

    Map.get(images, :medium) || Map.get(images, :large) ||
      Map.get(images, :small) || Map.get(images, :xl) || Map.get(vn, :image_url)
  end

  defp image_srcset(nil), do: nil

  defp image_srcset(vn) do
    images = images_for(vn)

    [
      {Map.get(images, :small), "128w"},
      {Map.get(images, :medium), "256w"},
      {Map.get(images, :large), "512w"},
      {Map.get(images, :xl), "1024w"}
    ]
    |> Enum.reject(fn {url, _w} -> is_nil(url) end)
    |> case do
      [] -> nil
      entries -> Enum.map_join(entries, ", ", fn {url, w} -> "#{url} #{w}" end)
    end
  end

  defp images_for(vn) do
    case Map.get(vn, :images) do
      images when is_map(images) and map_size(images) > 0 -> images
      _ -> VisualNovels.build_image_urls(vn)
    end
  end

  defp href_for(nil), do: nil
  defp href_for(%{slug: slug}) when is_binary(slug) and slug != "", do: "/vn/#{slug}"
  defp href_for(_), do: nil

  defp tooltip_title(false, _), do: nil
  defp tooltip_title(true, nil), do: nil

  defp tooltip_title(true, vn) do
    case Map.get(vn, :title) do
      title when is_binary(title) and title != "" -> title
      _ -> nil
    end
  end

  defp native_title(true, _), do: nil
  defp native_title(false, vn), do: vn && Map.get(vn, :title)

  defp nsfw_blur_size(sizes) when is_binary(sizes) do
    default_size =
      sizes
      |> String.split(",")
      |> List.last()
      |> String.trim()

    case Regex.run(~r/(\d+(?:\.\d+)?)px/, default_size) do
      [_, px] -> px
      _ -> "100"
    end
  end

  defp nsfw_blur_size(_sizes), do: "100"

  defp merge_styles(shadow?, style, nsfw_blur?, nsfw_blur_size) do
    [
      shadow? && @cover_shadow,
      nsfw_blur? && "--nsfw-blur-size: #{nsfw_blur_size};",
      style
    ]
    |> Enum.filter(&is_binary/1)
    |> case do
      [] -> nil
      styles -> Enum.join(styles, " ")
    end
  end
end
