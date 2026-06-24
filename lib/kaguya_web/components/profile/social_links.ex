defmodule KaguyaWeb.Components.Profile.SocialLinks do
  @moduledoc """
  Social-links row rendered inside the desktop bio sidebar (compact) and the
  bottom of the bio sheet on mobile (non-compact).

  Instagram and TikTok are intentionally not rendered; only the
  website + twitter glyphs show.
  """

  use KaguyaWeb, :html

  alias KaguyaWeb.Components.Shared.SocialIcons

  attr :website, :string, default: nil
  attr :twitter, :string, default: nil
  attr :instagram, :string, default: nil
  attr :tiktok, :string, default: nil
  attr :compact, :boolean, default: false

  def social_links(assigns) do
    if all_empty?(assigns) do
      ~H""
    else
      ~H"""
      <%= if @compact do %>
        <div class="flex items-center gap-3 pt-4 text-[rgb(var(--foreground-primary))]">
          <.social_link
            :if={@website}
            href={@website}
            label="Website"
            site="website"
            class="size-[18px]"
          />
          <.social_link
            :if={@twitter}
            href={twitter_url(@twitter)}
            label="Twitter"
            site="twitter"
            class="size-[18px]"
          />
        </div>
      <% else %>
        <div class="space-y-[15px] lg:border-b lg:border-[rgb(var(--border-divider))] lg:px-[27px] lg:pt-7 lg:pb-8">
          <span class="text-base font-semibold text-[rgb(var(--foreground-primary))] max-lg:text-lg max-lg:leading-[22px]">
            Social Links
          </span>
          <div class="flex items-center gap-4 text-[rgb(var(--foreground-primary))] lg:gap-5">
            <.social_link :if={@website} href={@website} label="Website" site="website" class="size-5" />
            <.social_link
              :if={@twitter}
              href={twitter_url(@twitter)}
              label="Twitter"
              site="twitter"
              class="size-5"
            />
          </div>
        </div>
      <% end %>
      """
    end
  end

  defp all_empty?(assigns) do
    Enum.all?([:website, :twitter, :instagram, :tiktok], fn k ->
      value = Map.get(assigns, k)
      is_nil(value) or value == ""
    end)
  end

  attr :href, :string, required: true
  attr :label, :string, required: true
  attr :site, :string, required: true
  attr :class, :any, default: "size-5"

  defp social_link(assigns) do
    ~H"""
    <a href={@href} target="_blank" rel="noopener noreferrer" aria-label={@label}>
      <SocialIcons.icon site={@site} class={@class} />
    </a>
    """
  end

  defp twitter_url(handle), do: "https://twitter.com/" <> handle
end
