defmodule KaguyaWeb.VN.Panels.Screenshots do
  @moduledoc """
  Screenshots tab.

  Hides NSFW / brutal screenshots based on the viewer's content
  preferences (`show_nsfw_screenshots` / `show_brutal_screenshots`).
  Logged-out viewers always get the strictest defaults (hide both).
  When anything is filtered out, a passive footer surfaces the count
  and links to the Settings page so users have one consistent path to
  adjust visibility.
  """

  use KaguyaWeb, :html

  import KaguyaWeb.AuthPromptComponents, only: [auth_link: 1]

  import KaguyaWeb.VN.PanelHelpers,
    only: [image_src: 2, map_value: 2, media_like_button: 1]

  attr :items, :list, required: true
  attr :show_nsfw, :boolean, default: false
  attr :show_brutal, :boolean, default: false
  attr :is_logged_in, :boolean, default: false
  attr :id_prefix, :string, default: "media-like"

  def panel(assigns) do
    {visible, hidden_count} = partition(assigns.items, assigns.show_nsfw, assigns.show_brutal)

    assigns =
      assigns
      |> assign(:visible, visible)
      |> assign(:hidden_count, hidden_count)

    ~H"""
    <%= if @visible == [] do %>
      <.hidden_footer count={@hidden_count} is_logged_in={@is_logged_in} />
    <% else %>
      <div class="grid grid-cols-3 gap-x-1.5 gap-y-3 lg:gap-x-2 lg:gap-y-5">
        <div
          :for={screenshot <- @visible}
          class="group relative transition-transform duration-200 ease-out lg:hover:scale-[1.02]"
        >
          <div class="overflow-hidden rounded-xl">
            <button
              type="button"
              phx-click="open_media_lightbox"
              phx-value-url={image_src(screenshot, [:large, :medium, :small])}
              phx-value-title="Screenshot"
              phx-value-subtitle={screenshot_label(screenshot)}
              class="block w-full cursor-pointer"
              title={screenshot_label(screenshot)}
              aria-label={"Open #{screenshot_label(screenshot)}"}
            >
              <img
                src={image_src(screenshot, [:medium, :small])}
                alt={screenshot_label(screenshot)}
                class="aspect-video w-full object-cover transition-[filter] duration-200 group-hover:brightness-[0.85]"
              />
            </button>
          </div>
          <.media_like_button
            id_prefix={@id_prefix}
            media={screenshot}
            event="toggle_screenshot_like"
            value_key="screenshot-id"
            noun="screenshot"
            is_logged_in={@is_logged_in}
          />
        </div>
      </div>

      <.hidden_footer count={@hidden_count} is_logged_in={@is_logged_in} />
    <% end %>
    """
  end

  attr :id, :string, required: true
  attr :state, :any, default: :not_loaded
  attr :current_user, :map, default: nil

  def preview(assigns) do
    items =
      case assigns.state do
        {:ok, items} -> items
        _ -> []
      end

    user = assigns.current_user || %{}

    {visible, _} =
      partition(
        items,
        Map.get(user, :show_nsfw_screenshots, false),
        Map.get(user, :show_brutal_screenshots, false)
      )

    assigns = assign(assigns, items: Enum.take(visible, 12), count: length(visible))

    ~H"""
    <section :if={@items != []} id={@id} aria-label="Screenshots" class="mt-5">
      <div class="grid grid-cols-3 gap-1 lg:grid-cols-6">
        <button
          :for={{screenshot, index} <- Enum.with_index(@items)}
          id={"#{@id}-#{screenshot.id}"}
          type="button"
          phx-click="open_media_lightbox"
          phx-value-kind="screenshots"
          phx-value-url={image_src(screenshot, [:large, :medium, :small])}
          aria-label={"Open screenshot #{index + 1}"}
          class={[
            "group overflow-hidden rounded-[3px] bg-white/5 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white",
            index >= 6 && "hidden lg:block"
          ]}
        >
          <img
            src={image_src(screenshot, [:small, :medium])}
            alt=""
            loading="lazy"
            class="aspect-video w-full object-cover transition duration-200 group-hover:scale-105 group-hover:brightness-110"
          />
        </button>
      </div>
      <button
        type="button"
        phx-click="open_media_lightbox"
        phx-value-kind="screenshots"
        class="mt-2 text-[11px] text-[rgb(var(--foreground-tertiary))] transition hover:text-[rgb(var(--foreground-primary))]"
      >
        View all {@count} screenshots <span aria-hidden="true">→</span>
      </button>
    </section>
    """
  end

  def skeleton(assigns) do
    ~H"""
    <div class="grid grid-cols-3 gap-x-1.5 gap-y-3 lg:gap-x-2 lg:gap-y-5">
      <div
        :for={_ <- 1..6}
        class="aspect-video w-full animate-pulse rounded-xl bg-[rgb(var(--surface-banner))]/40"
      >
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Hidden-count footer — kept passive and quiet so it never feels like
  # gating, just an explanation + one-tap adjust.
  # ---------------------------------------------------------------------------

  attr :count, :integer, required: true
  attr :is_logged_in, :boolean, default: false

  defp hidden_footer(assigns) do
    ~H"""
    <div
      :if={@count > 0}
      class="text-style-captionRegular mt-4 flex flex-wrap items-center justify-between gap-x-3 gap-y-1 rounded-md bg-white/4 px-3 py-2"
    >
      <p class="text-foreground-tertiary flex items-center gap-1.5">
        <Lucide.eye_off class="size-3 shrink-0" aria-hidden />
        <span>
          {@count} screenshot{if @count == 1, do: "", else: "s"} hidden by your content preferences
        </span>
      </p>
      <.auth_link
        href="/account/settings#content-preferences"
        is_logged_in={@is_logged_in}
        modal_id="vn-auth-prompt"
        auth_message="Sign in to adjust your content preferences"
        class="hover:text-foreground-primary text-foreground-secondary text-style-captionMedium underline-offset-2 transition-colors hover:underline"
      >
        Adjust
      </.auth_link>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp partition(items, show_nsfw, show_brutal) do
    {visible, hidden} =
      Enum.split_with(items, fn item ->
        not hidden_by_prefs?(item, show_nsfw, show_brutal)
      end)

    {visible, length(hidden)}
  end

  defp hidden_by_prefs?(screenshot, show_nsfw, show_brutal) do
    cond do
      map_value(screenshot, :is_nsfw) == true and not show_nsfw -> true
      map_value(screenshot, :is_brutal) == true and not show_brutal -> true
      true -> false
    end
  end

  defp screenshot_label(screenshot) do
    cond do
      map_value(screenshot, :is_nsfw) == true -> "NSFW screenshot"
      map_value(screenshot, :is_brutal) == true -> "Brutal screenshot"
      true -> "Screenshot"
    end
  end
end
