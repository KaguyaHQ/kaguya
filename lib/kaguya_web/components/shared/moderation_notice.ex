defmodule KaguyaWeb.SharedComponents.ModerationNotice do
  @moduledoc """
  Subtle inline notices for moderated content — locked threads and
  moderator removals. Uses neutral tokens and a small lead icon instead of
  bright amber/red banners.
  """

  use KaguyaWeb, :html

  attr :class, :any, default: nil
  attr :message, :string, default: "This post has been locked by the moderators."

  def locked_notice(assigns) do
    ~H"""
    <div class={[
      "relative z-10 flex items-center gap-2.5 rounded-[8px] border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-elevated))]/50 px-3 py-2.5 text-[rgb(var(--foreground-secondary))]",
      @class
    ]}>
      <Lucide.lock class="size-4 shrink-0 text-[rgb(var(--foreground-tertiary))]" aria-hidden />
      <p class="min-w-0 text-sm/5 text-[rgb(var(--foreground-tertiary))]">
        {@message}
      </p>
    </div>
    """
  end

  attr :class, :any, default: nil
  attr :item_label, :string, default: "post"
  attr :message, :string, default: nil

  def removal_notice(assigns) do
    assigns =
      assign(
        assigns,
        :resolved_message,
        assigns.message ||
          "Sorry, this #{assigns.item_label} has been removed by the moderators."
      )

    ~H"""
    <div class={[
      "relative z-10 flex items-center gap-2.5 rounded-[8px] border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-elevated))]/50 px-3 py-2.5 text-[rgb(var(--foreground-secondary))]",
      @class
    ]}>
      <Lucide.ban class="size-4 shrink-0 text-red-400" aria-hidden />
      <p class="min-w-0 text-sm/5 text-[rgb(var(--foreground-tertiary))]">
        {@resolved_message}
      </p>
    </div>
    """
  end
end
