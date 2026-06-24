defmodule KaguyaWeb.Components.Profile.Stats.Hero do
  @moduledoc """
  Hero header component for the profile stats dashboard.
  """

  use KaguyaWeb, :html

  import KaguyaWeb.Components.Profile.Stats.Charting

  alias KaguyaWeb.Format

  attr :profile, :map, required: true
  attr :stats, :map, required: true

  def stats_hero(assigns) do
    assigns =
      assigns
      |> assign(:hero, assigns.stats.hero)
      |> assign(:avatar_url, assigns.stats.avatar_url)
      |> assign(:hero_covers, Map.get(assigns.stats, :hero_covers, []))
      |> assign(:hours, round((assigns.stats.hero.read_time_minutes || 0) / 60))

    ~H"""
    <section class="relative flex justify-center overflow-hidden bg-[rgb(var(--surface-base))] pb-10 lg:pb-28">
      <div
        :if={@hero_covers != []}
        class="kaguya-stats-cover-wall pointer-events-none absolute inset-0 z-0 overflow-hidden select-none"
        aria-hidden="true"
      >
        <div class="kaguya-stats-cover-drift flex h-full w-max gap-2.5 opacity-[0.85]">
          <img
            :for={cover <- @hero_covers ++ @hero_covers}
            src={cover.src}
            alt=""
            loading="lazy"
            decoding="async"
            draggable="false"
            class="h-full w-auto max-w-none"
          />
        </div>
        <div
          class="absolute inset-0"
          style="background: radial-gradient(ellipse 72% 62% at 50% 44%, rgb(var(--surface-base) / 0.9), rgb(var(--surface-base) / 0.45) 50%, rgb(var(--surface-base) / 0) 100%);"
        >
        </div>
      </div>

      <div class="relative z-10 mt-10 flex flex-col items-center gap-6 px-4 lg:mt-16">
        <div class="flex flex-col items-center gap-2 lg:gap-5">
          <h1 class="font-source-serif text-[32px] leading-[1.1] font-semibold tracking-[-0.03em] text-[#EBF7FD] lg:text-[72px]">
            A Life in VNs
          </h1>

          <div class="flex items-center gap-2 lg:gap-3">
            <.link navigate={"/@#{@profile.username}"}>
              <KaguyaWeb.SharedComponents.UserAvatar.user_avatar
                user={
                  %{
                    avatar_url: @avatar_url,
                    username: @profile.username,
                    display_name: @profile.display_name
                  }
                }
                size="size-6 lg:size-9"
                sizes="(max-width: 1023px) 24px, 36px"
                class={["outline", "outline-1", "outline-white/20"]}
                fallback={:empty}
              />
            </.link>
            <p class="text-sm text-[rgb(var(--foreground-secondary))] max-lg:leading-[32px] lg:text-lg">
              <.link
                navigate={"/@#{@profile.username}"}
                class="text-[rgb(var(--foreground-primary))] hover:text-[rgb(var(--text-link-hover))]"
              >
                {@profile.display_name}
              </.link>
              <span class="text-[rgb(var(--foreground-quaternary))]">'s all-time stats</span>
            </p>
            <button
              type="button"
              data-share-button
              aria-label="Share stats"
              title="Share stats"
              class="flex h-[26px] w-[26px] shrink-0 items-center justify-center rounded-full border border-[rgb(var(--border-divider))] bg-linear-to-b from-[rgb(var(--button-background-brand-default))]/12 via-[rgb(var(--button-background-brand-default))]/4 to-[rgb(var(--button-background-brand-default))]/7 p-1 transition hover:bg-white/4 lg:h-[32px] lg:w-[32px] lg:p-2"
            >
              <Lucide.link_2
                class="size-3.5 text-[rgb(var(--foreground-primary))] lg:size-4"
                aria-hidden
              />
            </button>
          </div>

          <div class="mt-10 flex items-center gap-0 max-lg:divide-x max-lg:divide-[rgb(var(--border-divider))] lg:mt-16 lg:gap-14">
            <.hero_stat
              href={"/@#{@profile.username}/library/read"}
              label="VN"
              plural="VNs"
              count={@hero.vns_count}
            />
            <.hero_stat
              :if={@hero.reviews_count > 0}
              href={"/@#{@profile.username}/reviews"}
              label="Review"
              count={@hero.reviews_count}
            />
            <.hero_stat
              :if={@hero.lists_count > 0}
              href={"/@#{@profile.username}/lists"}
              label="List"
              count={@hero.lists_count}
            />
            <.hero_stat label="Hour" count={@hours} />
            <.hero_stat label="Developer" count={@hero.producers_count} />
          </div>
        </div>
      </div>
    </section>
    """
  end

  attr :href, :string, default: nil
  attr :label, :string, required: true
  attr :plural, :string, default: nil
  attr :count, :integer, required: true

  defp hero_stat(assigns) do
    ~H"""
    <%= if @href do %>
      <.link navigate={@href} class="group">
        <.hero_stat_content label={@label} plural={@plural} count={@count} />
      </.link>
    <% else %>
      <.hero_stat_content label={@label} plural={@plural} count={@count} />
    <% end %>
    """
  end

  attr :label, :string, required: true
  attr :plural, :string, default: nil
  attr :count, :integer, required: true

  defp hero_stat_content(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-2 max-lg:px-2.5 lg:min-w-[101px] lg:gap-1">
      <span class="text-base leading-[19px] font-semibold text-[#EBF7FD] tabular-nums lg:text-[48px] lg:leading-none lg:font-normal">
        {Format.integer(@count)}
      </span>
      <span class={[
        "text-[11px] leading-[15px] font-light text-[rgb(var(--foreground-quaternary))] transition-colors duration-150 group-hover:text-[rgb(var(--text-link-hover))] lg:text-[13px]/5 lg:font-normal lg:tracking-[0.04em]",
        is_nil(@plural) && "lg:uppercase"
      ]}>
        {pluralize(@count, @label, @plural || "#{@label}s")}
      </span>
    </div>
    """
  end
end
