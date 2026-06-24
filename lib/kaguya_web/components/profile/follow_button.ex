defmodule KaguyaWeb.Components.Profile.FollowButton do
  @moduledoc """
  Follow / unfollow button.

  Mirrors `FollowButton.tsx` for the default (non-custom-trigger) variant.
  Desktop hover swaps the "Following" label to "Unfollow"; mobile shows
  "Unfollow" directly when following.

  The component emits `phx-click="toggle_follow"` with `phx-value-user-id`;
  callers must handle the event (see `KaguyaWeb.ProfileLive.Events.toggle_follow/2`).
  Optimistic state lives on the parent LiveView assigns and is recomputed
  on every header reload.
  """

  use KaguyaWeb, :html

  attr :user_id, :string, required: true

  attr :follow_state, :atom,
    required: true,
    values: [:self, :following, :not_following],
    doc: "Resolved follow state for the viewer-to-target relationship."

  attr :is_logged_in, :boolean, default: false
  attr :variant, :atom, default: :brand, values: [:brand, :neutral, :neutral_inverse]
  attr :class, :any, default: nil

  def follow_button(%{follow_state: :self} = assigns) do
    ~H""
  end

  def follow_button(assigns) do
    following? = assigns.follow_state == :following

    assigns =
      assigns
      |> assign(:following?, following?)
      |> assign(:label_default, if(following?, do: "Following", else: "Follow"))
      |> assign(:label_hover, if(following?, do: "Unfollow", else: "Follow"))
      |> assign(:label_mobile, if(following?, do: "Unfollow", else: "Follow"))

    ~H"""
    <button
      type="button"
      phx-click="toggle_follow"
      phx-value-user-id={@user_id}
      data-following={if @following?, do: "true", else: "false"}
      data-logged-in={if @is_logged_in, do: "true", else: "false"}
      aria-pressed={if @following?, do: "true", else: "false"}
      class={[
        "group relative flex h-[46px] min-w-[124px] items-center justify-center gap-2 rounded-[6px] px-4 py-3 font-medium transition-all duration-300 max-lg:h-[33px] max-lg:min-w-0 max-lg:rounded-[6px] max-lg:px-6 max-lg:py-1.5",
        variant_classes(@variant, @following?),
        @class
      ]}
    >
      <span class="max-lg:hidden">
        <span class={[!@following? && "block", @following? && "group-hover:hidden"]}>
          {@label_default}
        </span>
        <span :if={@following?} class="hidden group-hover:block">
          {@label_hover}
        </span>
      </span>
      <span class="lg:hidden">{@label_mobile}</span>
    </button>
    """
  end

  defp variant_classes(_variant, true = _following?) do
    "bg-[rgb(var(--surface-elevated))] text-[rgb(var(--foreground-primary))] hover:bg-white/[6%]"
  end

  defp variant_classes(:neutral, false) do
    "bg-[rgb(var(--button-background-neutral-default))] text-[rgb(var(--foreground-primary))] hover:bg-[rgb(var(--button-background-neutral-hover))]"
  end

  defp variant_classes(:neutral_inverse, false) do
    "bg-[rgb(var(--foreground-primary))] text-[rgb(var(--surface-base))] hover:opacity-90"
  end

  defp variant_classes(:brand, false) do
    "bg-[rgb(var(--button-background-brand-default))] text-white hover:bg-[rgb(var(--button-background-brand-hover))]"
  end
end
