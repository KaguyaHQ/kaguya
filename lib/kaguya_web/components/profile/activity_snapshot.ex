defmodule KaguyaWeb.Components.Profile.ActivitySnapshot do
  @moduledoc """
  Right-sidebar activity snapshot rendered on the overview tab.

  Vertical timeline (dot + connecting line) with verb sentences in muted
  text and the entity name as a bold link. Read-only — no optimistic UI.
  """

  use KaguyaWeb, :html

  alias KaguyaWeb.Components.Activity.Helpers, as: ActivityHelpers
  alias KaguyaWeb.SharedComponents.Time, as: SharedTime

  attr :items, :list, required: true
  attr :username, :string, required: true
  attr :display_name, :string, required: true

  def activity_snapshot(assigns) do
    if assigns.items == [] do
      ~H""
    else
      ~H"""
      <div class="flex flex-col lg:py-[18px]">
        <div class="flex w-full items-center justify-between lg:border-b lg:border-[rgb(var(--border-divider))] lg:py-2">
          <.link
            navigate={"/@#{@username}/activity"}
            class="text-sm text-[rgb(var(--foreground-primary))] lg:hover:text-[rgb(var(--text-link-hover))]"
          >
            Activity
          </.link>
        </div>

        <div class="relative flex flex-col lg:pt-4">
          <.snapshot_item
            :for={{item, idx} <- Enum.with_index(@items)}
            item={item}
            username={@username}
            display_name={@display_name}
            is_last={idx == length(@items) - 1}
          />
        </div>
      </div>
      """
    end
  end

  attr :item, :map, required: true
  attr :username, :string, required: true
  attr :display_name, :string, required: true
  attr :is_last, :boolean, required: true

  defp snapshot_item(assigns) do
    item = assigns.item
    metadata = ActivityHelpers.normalize_metadata(item.metadata)
    verb = verb_for(item, metadata, assigns.username)

    assigns =
      assigns
      |> assign(:metadata, metadata)
      |> assign(:verb, verb)
      |> assign(:date_label, SharedTime.calendar_custom(item.inserted_at))
      |> assign(:comment_preview, comment_preview(item.action, metadata))

    ~H"""
    <div class="flex items-stretch gap-3">
      <div class="relative flex w-[11px] shrink-0 flex-col items-center">
        <div class="relative z-10 mt-[4.5px] size-[9px] shrink-0 rounded-full bg-[rgb(var(--foreground-tertiary))]" />
        <div
          :if={not @is_last}
          class="absolute top-[13.5px] -bottom-[4.5px] left-1/2 w-px -translate-x-1/2 bg-[rgb(var(--foreground-tertiary))]/30"
        />
      </div>

      <div class="min-w-0 flex-1 pb-4">
        <p class="text-[12px] leading-[18px] text-[rgb(var(--foreground-tertiary))]">
          <.link
            navigate={"/@#{@username}"}
            class="font-medium text-[rgb(var(--foreground-secondary))] hover:text-[rgb(var(--text-link-hover))]"
          >
            {@display_name}
          </.link>
          {" "}
          {@verb.text}
          <%= if @verb.target do %>
            {" "}
            <%= if @verb.target_href do %>
              <.link
                navigate={@verb.target_href}
                class="font-medium text-[rgb(var(--foreground-secondary))] hover:text-[rgb(var(--text-link-hover))]"
              >
                {@verb.target}
              </.link>
            <% else %>
              <span class="font-medium text-[rgb(var(--foreground-secondary))]">
                {@verb.target}
              </span>
            <% end %>
          <% end %>
          <%= if @verb.suffix do %>
            {" "}{@verb.suffix}
          <% end %>
          {" "}
          <span class="text-[11px] leading-[16px] whitespace-nowrap text-[rgb(var(--foreground-quaternary))]">
            {@date_label}
          </span>
        </p>
        <p
          :if={@comment_preview}
          class="mt-0.5 line-clamp-1 text-[11px] leading-[16px] text-[rgb(var(--foreground-tertiary))] italic"
        >
          "{@comment_preview}"
        </p>
      </div>
    </div>
    """
  end

  defp comment_preview(:commented, %{} = m) do
    preview = m["text_preview"]
    if ActivityHelpers.present?(preview), do: preview
  end

  defp comment_preview(_, _), do: nil

  # Flatten the shared verb/href source of truth (`Activity.Helpers`, the same
  # one the activity tab and home rail use) into the snapshot's single-link
  # model: one bold target link plus a plain-text suffix. `target_href/6`
  # returns the "#" sentinel for "no link"; we map that to nil so the template
  # renders plain text instead of a dead anchor.
  defp verb_for(item, metadata, feed_username) do
    verb =
      ActivityHelpers.activity_verb(
        item.action,
        metadata,
        item.followed_user,
        item.followed_producer,
        item.entity_ref
      )

    href =
      ActivityHelpers.target_href(
        item.action,
        metadata,
        feed_username,
        item.followed_user,
        item.followed_producer,
        item.entity_ref
      )

    %{
      text: verb.text,
      target: verb.target,
      target_href: if(href in [nil, "#"], do: nil, else: href),
      suffix: Map.get(verb, :suffix)
    }
  end
end
