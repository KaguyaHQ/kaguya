defmodule KaguyaWeb.SharedComponents.CharacterImage do
  @moduledoc """
  Shared character portrait — Phoenix-side port of
  `../personal/legacy-next-app/src/components/shared/CharacterImage.tsx`.

  Mirrors `KaguyaWeb.SharedComponents.Cover` for the character side:
  resolved srcset, NSFW blur, fallback, optional name tooltip attr.

  Why a separate module from `Cover`?
    * Aspect ratio: `1:1` for characters vs. `2:3` for VN covers.
    * NSFW comes from `:is_image_nsfw` / `:is_image_suggestive` on the
      character itself, same as covers.
    * No `link={true}` wrapper — character cards are typically linked
      by their parent (the card row), not by the image alone.

  See `docs/migrations/nextjs-liveview/plans/component-parity-plan.md` § 6.

  ## Example

      <.character_image
        character={@character}
        sizes="(max-width: 768px) 25vw, 120px"
        class="aspect-square w-full"
      />
  """

  use KaguyaWeb, :html

  alias Kaguya.VisualNovels

  attr :character, :map,
    required: true,
    doc: "Map with `:images` (or buildable via `VisualNovels.build_character_image_urls/1`)."

  attr :sizes, :string, default: nil, doc: "HTML `sizes` attribute for `srcset`."

  attr :class, :any,
    default: "aspect-square w-full object-cover object-top",
    doc: "Classes for the image element."

  attr :fallback_class, :any,
    default: "aspect-square w-full bg-[rgb(var(--surface-elevated))]",
    doc: "Classes for the no-image fallback."

  attr :rounded, :string, default: "rounded-[4px]"
  attr :loading, :string, default: "lazy", values: ["lazy", "eager"]
  attr :fetchpriority, :string, default: nil
  attr :alt, :string, default: nil

  attr :blur_nsfw, :boolean,
    default: true,
    doc: "Apply the production NSFW blur when the character image is NSFW/suggestive."

  attr :enable_nsfw_reveal, :boolean,
    default: false,
    doc: "Allow click-to-reveal on a blurred NSFW image (handled by the shared JS hook)."

  attr :show_name_tooltip, :boolean,
    default: false,
    doc: "Stamps `data-character-name` for the tooltip provider."

  attr :rest, :global

  def character_image(assigns) do
    assigns =
      assigns
      |> assign(:image_urls, image_urls(assigns.character))
      |> assign(:name, Map.get(assigns.character, :name))
      |> assign(:adult_image?, adult_image?(assigns.character))
      |> assign(:alt, assigns.alt || Map.get(assigns.character, :name) || "")

    assigns =
      assigns
      |> assign(:src, primary_src(assigns.image_urls))
      |> assign(:srcset, srcset(assigns.image_urls))
      |> assign(:nsfw_blur_size, nsfw_blur_size(assigns.sizes))

    ~H"""
    <%= if @src do %>
      <img
        src={@src}
        srcset={@srcset}
        sizes={@sizes}
        alt={@alt}
        title={if @show_name_tooltip, do: nil, else: @name}
        data-character-name={if @show_name_tooltip, do: @name}
        data-nsfw-blur={if @adult_image? and @blur_nsfw, do: "1"}
        data-nsfw-reveal={if @adult_image? and @blur_nsfw and @enable_nsfw_reveal, do: "1"}
        style={if @adult_image? and @blur_nsfw, do: "--nsfw-blur-size: #{@nsfw_blur_size};"}
        loading={@loading}
        fetchpriority={@fetchpriority}
        decoding="async"
        class={[@class, @rounded, "object-top"]}
        {@rest}
      />
    <% else %>
      <span
        class={[@fallback_class, @rounded, "block"]}
        title={if @show_name_tooltip, do: nil, else: @name}
        data-character-name={if @show_name_tooltip, do: @name}
        {@rest}
      />
    <% end %>
    """
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp image_urls(character) when is_map(character) do
    case Map.get(character, :images) || Map.get(character, "images") do
      %{} = urls -> urls
      _ -> safely_build(character)
    end
  end

  defp image_urls(_), do: %{}

  defp safely_build(character) do
    if function_exported?(VisualNovels, :build_character_image_urls, 1) do
      VisualNovels.build_character_image_urls(character) || %{}
    else
      %{}
    end
  end

  defp primary_src(urls) do
    Map.get(urls, :large) || Map.get(urls, "large") ||
      Map.get(urls, :small) || Map.get(urls, "small") ||
      Map.get(urls, :medium) || Map.get(urls, "medium")
  end

  defp srcset(urls) do
    [
      {Map.get(urls, :small) || Map.get(urls, "small"), "240w"},
      {Map.get(urls, :large) || Map.get(urls, "large"), "660w"}
    ]
    |> Enum.reject(fn {url, _w} -> is_nil(url) or url == "" end)
    |> case do
      [] -> nil
      [_only] -> nil
      entries -> Enum.map_join(entries, ", ", fn {url, w} -> "#{url} #{w}" end)
    end
  end

  defp adult_image?(character) when is_map(character) do
    [
      :is_image_nsfw,
      :is_image_suggestive,
      "is_image_nsfw",
      "is_image_suggestive"
    ]
    |> Enum.any?(&(Map.get(character, &1) == true))
  end

  defp adult_image?(_), do: false

  defp nsfw_blur_size(nil), do: "100"

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
end
