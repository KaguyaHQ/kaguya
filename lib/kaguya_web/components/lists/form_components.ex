defmodule KaguyaWeb.Lists.FormComponents do
  @moduledoc false

  use KaguyaWeb, :html

  import KaguyaWeb.UI.Menu

  alias KaguyaWeb.SharedComponents.Search, as: SharedSearch

  @type form_values :: %{optional(String.t()) => term()}
  @tier_color_options [
    "#f87171",
    "#fb923c",
    "#facc15",
    "#4ade80",
    "#34d399",
    "#22d3ee",
    "#60a5fa",
    "#a78bfa",
    "#f472b6",
    "#94a3b8"
  ]
  @max_tier_count 10

  attr :title, :string, required: true
  attr :edit_mode, :boolean, default: false
  attr :saving, :boolean, default: false
  attr :deleting, :boolean, default: false
  attr :save_disabled, :boolean, default: false

  def mobile_navbar(assigns) do
    ~H"""
    <nav
      style="box-shadow: 0px 4px 10px rgba(0, 0, 0, 0.30)"
      class="fixed inset-x-0 top-0 z-30 flex items-center justify-between bg-[rgb(var(--surface-base))] px-5 py-[7px] lg:hidden"
    >
      <div class="flex items-center gap-6">
        <button
          type="button"
          phx-click="cancel"
          disabled={@saving}
          class="flex size-11 items-center justify-center rounded-full bg-white/2 p-0 text-[rgb(var(--foreground-primary))] transition hover:bg-white/6 disabled:opacity-50"
          aria-label="Cancel"
        >
          <.icon name={:x} class="size-[18px]" />
        </button>

        <h2 class="text-xl/7 font-semibold text-[rgb(var(--foreground-primary))]">
          {@title}
        </h2>
      </div>

      <div class="flex items-center gap-2">
        <button
          :if={@edit_mode}
          type="button"
          phx-click="confirm_delete"
          disabled={@deleting or @saving}
          class="p-2 text-sm font-normal text-[rgb(var(--foreground-secondary))] transition-colors hover:text-red-500 disabled:opacity-50"
        >
          Delete
        </button>

        <button
          type="submit"
          form="list-form"
          disabled={@saving or @save_disabled}
          class="flex size-11 items-center justify-center rounded-full bg-white/2 p-0 text-[rgb(var(--foreground-primary))] transition hover:bg-white/6 disabled:opacity-50"
          aria-label="Save"
        >
          <span
            :if={@saving}
            class="size-5 animate-spin rounded-full border-2 border-[rgb(var(--foreground-tertiary))] border-t-[rgb(var(--foreground-primary))]"
          >
          </span>
          <.icon :if={!@saving} name={:check} class="size-5" />
        </button>
      </div>
    </nav>
    """
  end

  attr :form, :any, required: true
  attr :values, :map, required: true

  def metadata_fields(assigns) do
    assigns =
      assigns
      |> assign(:is_public, bool_value(assigns.values, "is_public", true))
      |> assign(:is_ranked, bool_value(assigns.values, "is_ranked", false))
      |> assign(:display_mode, display_mode(assigns.values))
      |> assign(:description_length, description_length(assigns.form))

    ~H"""
    <input type="hidden" name={@form[:is_public].name} value={to_string(@is_public)} />
    <input type="hidden" name={@form[:is_ranked].name} value={to_string(@is_ranked)} />
    <input type="hidden" name={@form[:display_mode].name} value={@display_mode} />

    <div class="flex gap-8">
      <div class="flex w-full flex-col lg:w-1/2">
        <div class="space-y-6">
          <div class="space-y-2">
            <label
              for={@form[:name].id}
              class="block text-sm font-normal text-[rgb(var(--foreground-primary))]"
            >
              Name
            </label>
            <input
              id={@form[:name].id}
              name={@form[:name].name}
              type="text"
              value={input_value(@form, :name)}
              phx-debounce="blur"
              class="h-11 w-full rounded-[8px] border border-[rgb(var(--text-field-border))] bg-[rgb(var(--text-field-bg))] px-3.5 py-3 text-sm/5 text-[rgb(var(--foreground-primary))] placeholder:text-[rgb(var(--text-field-placeholder-text))] focus:border-[rgb(var(--text-field-border-focus))] focus:outline-none lg:px-3 lg:py-3.5 lg:text-sm/5"
            />
            <.field_errors field={@form[:name]} />
          </div>

          <div class="relative space-y-2 lg:hidden">
            <label
              for={@form[:description].id <> "-mobile"}
              class="block text-sm font-normal text-[rgb(var(--foreground-primary))]"
            >
              Description
            </label>
            <textarea
              id={@form[:description].id <> "-mobile"}
              name={@form[:description].name}
              placeholder="What's this list about?"
              phx-debounce="400"
              class="h-[104px] w-full resize-none rounded-[8px] border border-[rgb(var(--text-field-border))] bg-[rgb(var(--text-field-bg))] px-3.5 py-3 text-sm/5 text-[rgb(var(--foreground-primary))] placeholder:text-[rgb(var(--text-field-placeholder-text))] focus:border-[rgb(var(--text-field-border-focus))] focus:outline-none"
            ><%= input_value(@form, :description) %></textarea>

            <div
              :if={@description_length >= 450}
              class={[
                "absolute right-1 bottom-1 shrink-0 rounded-[4px] bg-[rgb(var(--surface-base))] px-2 py-1 text-right text-xs",
                if(@description_length > 500,
                  do: "text-red-400",
                  else: "text-[rgb(var(--foreground-primary))]/40"
                )
              ]}
            >
              {@description_length}/500
            </div>

            <.field_errors field={@form[:description]} class="text-xs" />
          </div>

          <div class="space-y-2">
            <label class="block text-sm font-medium text-[rgb(var(--foreground-primary))] lg:text-xs">
              Layout
            </label>
            <div class="grid h-8 grid-cols-2 rounded-[7px] border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-elevated))] p-0.5 lg:h-8">
              <button
                id="list-form-display-grid"
                type="button"
                phx-click="set_display_mode"
                phx-value-mode="grid"
                class={[
                  "flex items-center justify-center gap-1.5 rounded-[5px] text-xs transition-colors lg:text-[13px]",
                  if(@display_mode == "grid",
                    do: "bg-white/10 text-[rgb(var(--foreground-primary))]",
                    else:
                      "text-[rgb(var(--foreground-secondary))] hover:text-[rgb(var(--foreground-primary))]"
                  )
                ]}
              >
                <.icon name={:grid} class="size-3.5" /> Grid
              </button>
              <button
                id="list-form-display-tier"
                type="button"
                phx-click="set_display_mode"
                phx-value-mode="tier"
                class={[
                  "flex items-center justify-center gap-1.5 rounded-[5px] text-xs transition-colors lg:text-[13px]",
                  if(@display_mode == "tier",
                    do: "bg-white/10 text-[rgb(var(--foreground-primary))]",
                    else:
                      "text-[rgb(var(--foreground-secondary))] hover:text-[rgb(var(--foreground-primary))]"
                  )
                ]}
              >
                <.icon name={:rows} class="size-3.5" /> Tier
              </button>
            </div>

            <button
              :if={@display_mode == "tier"}
              id="list-form-tier-settings"
              type="button"
              phx-click="open_tier_editor"
              class="mt-2 flex h-10 w-full items-center justify-center gap-2 rounded-[8px] border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-elevated))] text-sm font-normal text-[rgb(var(--foreground-primary))] transition hover:bg-white/8"
            >
              <.icon name={:settings} class="size-4" /> Customize tiers
            </button>

            <div :if={@display_mode == "grid"} class="mt-2 flex items-center gap-2">
              <button
                type="button"
                role="switch"
                aria-checked={to_string(@is_ranked)}
                phx-click="toggle_flag"
                phx-value-field="is_ranked"
                class={[
                  "relative h-4 w-7 shrink-0 rounded-full transition",
                  if(@is_ranked,
                    do: "bg-[rgb(var(--foreground-primary))]",
                    else: "bg-[rgb(var(--border-divider))]"
                  )
                ]}
              >
                <span class={[
                  "absolute top-0.5 left-0.5 size-3 rounded-full bg-[rgb(var(--surface-base))] transition-transform",
                  @is_ranked && "translate-x-3"
                ]}>
                </span>
              </button>
              <div class="flex items-center gap-1.5">
                <p class="text-[13px]/5 font-normal text-[rgb(var(--foreground-primary))]">
                  Ranked list
                </p>
                <span
                  tabindex="0"
                  aria-label="Ranks VNs by your chosen order"
                  class="group relative inline-flex cursor-default text-[rgb(var(--foreground-secondary))]"
                >
                  <.icon name={:info} class="size-3.5" />
                  <span
                    role="tooltip"
                    class="pointer-events-none absolute top-1/2 left-full z-50 ml-2 w-max max-w-[220px] -translate-y-1/2 rounded-[4px] bg-[rgb(var(--button-background-neutral-inverse-default))] px-2 py-1.5 text-xs/4 font-medium text-[rgb(var(--button-text-on-neutral-inverse))] opacity-0 shadow-[0_4px_4px_rgba(0,0,0,0.25)] transition-opacity group-hover:opacity-100 group-focus-visible:opacity-100"
                  >
                    Ranks VNs by your chosen order
                  </span>
                </span>
              </div>
            </div>
          </div>

          <div class="space-y-2">
            <p class="text-sm font-medium text-[rgb(var(--foreground-primary))] lg:text-xs">
              Who can see this list
            </p>
            <.menu
              id="list-form-privacy"
              align="start"
              match_width
              class="flex h-11 w-full cursor-pointer items-center justify-between rounded-[8px] border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-elevated))] px-3 py-3.5 text-sm leading-none font-normal text-[rgb(var(--foreground-primary))]"
            >
              <:trigger aria-label="Who can see this list">
                <span class="flex items-center gap-[9px]">
                  <.icon name={if @is_public, do: :globe, else: :lock} class="size-4" />
                  <span>{if @is_public, do: "Anyone", else: "Only you"}</span>
                </span>
                <.icon name={:chevron_down} class="size-5 text-[rgb(var(--foreground-primary))]/40" />
              </:trigger>
              <div class="w-full overflow-hidden rounded-[12px] border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-menu-item-default))] p-0 shadow-2xl">
                <.menu_item
                  event="set_flag"
                  value={%{field: "is_public", value: "true"}}
                  class="flex h-auto w-full cursor-pointer items-center gap-[9px] rounded-none bg-transparent px-3 py-2 text-left text-sm font-normal text-[rgb(var(--foreground-primary))] transition hover:bg-[rgb(var(--surface-menu-item-hover))] [&_svg]:mr-0"
                  aria-current={if @is_public, do: "true"}
                >
                  <.icon name={:globe} class="size-4" />
                  <span>Anyone</span>
                </.menu_item>
                <.menu_item
                  event="set_flag"
                  value={%{field: "is_public", value: "false"}}
                  class="flex h-auto w-full cursor-pointer items-center gap-[9px] rounded-none bg-transparent px-3 py-2 text-left text-sm font-normal text-[rgb(var(--foreground-primary))] transition hover:bg-[rgb(var(--surface-menu-item-hover))] [&_svg]:mr-0"
                  aria-current={if not @is_public, do: "true"}
                >
                  <.icon name={:lock} class="size-4" />
                  <span>Only you</span>
                </.menu_item>
              </div>
            </.menu>
            <.field_errors field={@form[:is_public]} />
          </div>
        </div>
      </div>

      <div class="flex w-full flex-col self-stretch max-lg:hidden lg:w-1/2">
        <div class="flex h-full flex-col space-y-2">
          <label
            for={@form[:description].id}
            class="text-sm font-normal text-[rgb(var(--foreground-primary))]"
          >
            Description
          </label>
          <textarea
            id={@form[:description].id}
            name={@form[:description].name}
            placeholder="What's this list about?"
            phx-debounce="400"
            class="min-h-[160px] flex-1 resize-none rounded-[8px] border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-elevated))] px-3 py-3.5 text-sm text-[rgb(var(--foreground-primary))] placeholder:text-[rgb(var(--text-field-placeholder-text))] focus:border-[rgb(var(--text-field-border-focus))] focus:outline-none"
          ><%= input_value(@form, :description) %></textarea>
          <div class="flex w-full items-center justify-between">
            <div><.field_errors field={@form[:description]} class="text-xs" /></div>
            <div
              :if={@description_length >= 450}
              class={[
                "shrink-0 text-right text-xs",
                if(@description_length > 500,
                  do: "text-red-500",
                  else: "text-[rgb(var(--foreground-secondary))]"
                )
              ]}
            >
              {@description_length}/500
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :query, :string, default: ""
  attr :results, :list, default: []
  attr :error, :string, default: nil
  attr :loading, :boolean, default: false
  attr :placeholder, :string, default: "Search visual novels…"
  attr :class, :string, default: nil
  attr :results_class, :string, default: nil

  def search_box(assigns) do
    ~H"""
    <SharedSearch.vn_compact_search
      id={@id}
      query={@query}
      results={@results}
      error={@error}
      loading={@loading}
      debounce={0}
      placeholder={@placeholder}
      class={@class}
      results_class={@results_class}
      show_add_icon
    />
    """
  end

  attr :show, :boolean, default: false
  attr :query, :string, default: ""
  attr :results, :list, default: []
  attr :error, :string, default: nil
  attr :loading, :boolean, default: false

  def mobile_search_overlay(assigns) do
    ~H"""
    <div
      :if={@show}
      class="fixed inset-0 z-100 flex flex-col bg-[rgb(var(--surface-base))] lg:hidden"
    >
      <div class="flex items-center gap-3 border-b border-white/5 px-4 py-3">
        <button
          type="button"
          phx-click="close_mobile_search"
          class="flex size-11 shrink-0 items-center justify-center p-0 text-[rgb(var(--foreground-primary))]"
          aria-label="Close search"
        >
          <.icon name={:arrow_left} class="size-5" />
        </button>
        <.form
          for={%{}}
          as={:search}
          id="mobile-list-vn-search"
          phx-change="search"
          phx-submit="search"
          class="relative min-w-0 flex-1"
        >
          <.icon
            name={:search}
            class="pointer-events-none absolute top-1/2 left-4 size-4 -translate-y-1/2 text-[rgb(var(--foreground-tertiary))]"
          />
          <input
            type="search"
            name="search[query]"
            value={@query}
            placeholder="Search visual novels…"
            autocomplete="off"
            phx-debounce="350"
            class="h-11 w-full rounded-full border-none bg-[rgb(var(--surface-elevated))] pr-4 pl-11 text-sm/5 text-[rgb(var(--foreground-primary))] placeholder:text-[rgb(var(--foreground-tertiary))] focus:outline-none"
          />
        </.form>
      </div>

      <div class="flex-1 overflow-y-auto p-4">
        <div
          :if={@loading and @results == [] and !@error}
          class="flex h-[280px] items-center justify-center"
          role="status"
          aria-label="Searching"
        >
          <div class="kaguya-button-loader">
            <span class="kaguya-button-loader-bar"></span>
            <span class="kaguya-button-loader-bar" style="animation-delay: -0.2s"></span>
            <span class="kaguya-button-loader-bar" style="animation-delay: -0.4s"></span>
          </div>
        </div>
        <p
          :if={@error && !@loading}
          class="flex h-[280px] items-center justify-center text-sm text-[rgb(var(--foreground-tertiary))]"
        >
          Something went wrong
        </p>
        <p
          :if={!@error and !@loading and String.trim(@query || "") != "" and @results == []}
          class="flex h-[280px] items-center justify-center text-sm text-[rgb(var(--foreground-tertiary))]"
        >
          No matches
        </p>
        <div :if={!@error and @results != []} class="space-y-1">
          <button
            :for={result <- @results}
            type="button"
            phx-click="add_item"
            phx-value-id={result.id}
            class="flex w-full items-center gap-4 rounded-lg p-3 text-left transition-colors hover:bg-[rgb(var(--surface-menu-item-hover))] active:bg-[rgb(var(--surface-menu-item-pressed))]"
          >
            <.mobile_cover item={result} />
            <span class="min-w-0 flex-1">
              <span class="line-clamp-2 text-sm/5 font-medium text-[rgb(var(--foreground-primary))]">
                {result.title}
              </span>
              <span
                :if={result[:producers]}
                class="mt-1 line-clamp-1 text-xs leading-[18px] text-[rgb(var(--foreground-tertiary))]"
              >
                {producer_text(result[:producers])}
              </span>
            </span>
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :items, :list, default: []
  attr :tiers, :list, default: []
  attr :display_mode, :string, default: "grid"
  attr :is_ranked, :boolean, default: false
  attr :item_error, :any, default: nil

  def item_surface(assigns) do
    ~H"""
    <section class="flex flex-1 flex-col gap-5">
      <p :if={@item_error} role="alert" class="mt-2 text-sm font-medium text-[#E5484D]">
        {@item_error}
      </p>

      <div class={if @items != [], do: "lg:min-h-[65vh]", else: ""}>
        <%= cond do %>
          <% @items == [] -> %>
            <div class="flex items-center justify-center py-20 lg:py-28">
              <span class="text-sm text-[rgb(var(--foreground-secondary))]">
                Add visual novels that belong on this list
              </span>
            </div>
          <% @display_mode == "tier" -> %>
            <.tier_surface items={@items} tiers={@tiers} is_ranked={@is_ranked} />
          <% true -> %>
            <.grid_surface items={@items} is_ranked={@is_ranked} />
        <% end %>
      </div>

      <button
        type="button"
        phx-click="open_mobile_search"
        class="sticky bottom-6 mt-auto ml-auto flex size-14 items-center justify-center rounded-full bg-[rgb(var(--button-background-brand-default))] text-[rgb(var(--button-text-on-brand))] shadow-2xl transition hover:bg-[rgb(var(--button-background-brand-hover))] lg:hidden"
        aria-label="Add visual novel"
      >
        <.icon name={:plus} class="size-6" />
      </button>
    </section>
    """
  end

  attr :dialog, :atom, default: nil
  attr :deleting, :boolean, default: false

  def confirm_dialog(assigns) do
    ~H"""
    <div
      :if={@dialog}
      class="fixed inset-0 z-70 flex items-center justify-center bg-black/60 px-5"
      role="presentation"
    >
      <div
        :if={@dialog == :discard}
        role="dialog"
        aria-modal="true"
        aria-labelledby="discard-dialog-title"
        class="w-full max-w-[360px] rounded-[16px] bg-[rgb(var(--surface-base))] p-6 shadow-2xl"
      >
        <p id="discard-dialog-title" class="text-lg font-medium text-[rgb(var(--foreground-primary))]">
          Discard changes?
        </p>
        <p class="mt-2 text-sm font-normal text-[rgb(var(--foreground-secondary))]">
          Your changes haven't been saved.
        </p>

        <div class="mt-5 flex justify-end gap-2">
          <button
            type="button"
            phx-click="discard_changes"
            class="h-[41px] min-w-[74px] rounded-[8px] bg-[rgb(var(--button-background-destructive-default))] px-4 py-3 text-sm font-normal text-white transition hover:bg-[rgb(var(--button-background-destructive-hover))]"
          >
            Discard
          </button>
          <button
            type="button"
            phx-click="close_dialog"
            class="h-[41px] rounded-[8px] bg-[rgb(var(--surface-elevated))] px-4 py-3 text-sm font-normal text-[rgb(var(--foreground-primary))] transition hover:bg-white/8"
          >
            Keep editing
          </button>
        </div>
      </div>

      <div
        :if={@dialog == :delete}
        role="dialog"
        aria-modal="true"
        aria-labelledby="delete-dialog-title"
        class="w-full max-w-[437px] overflow-hidden rounded-t-[12px] rounded-b-[16px] bg-[rgb(var(--surface-base))] shadow-2xl"
      >
        <div class="flex items-center justify-between gap-2 border-b border-[rgb(var(--border-divider))] py-3.5 pr-[21px] pl-6">
          <p
            id="delete-dialog-title"
            class="flex items-center gap-2 text-lg font-medium text-[rgb(var(--foreground-primary))]"
          >
            <.icon name={:warning} class="size-5 text-[rgb(var(--foreground-error))]" />
            <span>Delete List?</span>
          </p>
          <button
            type="button"
            phx-click="close_dialog"
            class="flex size-11 items-center rounded-full border border-[rgb(var(--border-divider))] bg-transparent p-3 text-[rgb(var(--foreground-primary))] transition hover:bg-[rgb(var(--surface-elevated))]"
            aria-label="Close"
          >
            <.icon name={:x} class="size-5" />
          </button>
        </div>

        <div class="px-[26px] py-6">
          <p class="text-sm font-normal text-[rgb(var(--foreground-secondary))]">
            This will permanently delete your list. This action cannot be undone.
          </p>

          <div class="mt-4 flex w-full items-center justify-end gap-2">
            <button
              type="button"
              phx-click="close_dialog"
              class="flex h-[41px] items-center gap-2 rounded-[8px] bg-[rgb(var(--surface-elevated))] px-4 py-3 text-sm font-normal text-[rgb(var(--foreground-primary))] transition hover:bg-white/8"
            >
              Cancel
            </button>

            <button
              type="button"
              phx-click="delete"
              disabled={@deleting}
              class="ml-0 flex h-[41px] min-w-[74px] items-center justify-center gap-2 rounded-[8px] bg-[rgb(var(--button-background-destructive-default))] px-4 py-3 text-sm font-normal text-white transition hover:bg-[rgb(var(--button-background-destructive-hover))] disabled:opacity-50"
            >
              <span
                :if={@deleting}
                class="size-3 animate-spin rounded-full border-2 border-white/40 border-t-white"
              >
              </span>
              Delete
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :open, :boolean, default: false
  attr :tiers, :list, default: []

  def tier_dialog(assigns) do
    assigns =
      assigns
      |> assign(:colors, @tier_color_options)
      |> assign(:can_add_tier, length(assigns.tiers || []) < @max_tier_count)

    ~H"""
    <div
      :if={@open}
      class="fixed inset-0 z-80 flex items-center justify-center bg-black/60 px-5"
      role="presentation"
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="tier-dialog-title"
        class="w-full max-w-[500px] overflow-hidden rounded-[12px] bg-[rgb(var(--surface-base))] shadow-2xl"
      >
        <div class="border-b border-[rgb(var(--border-divider))] px-5 py-4">
          <p
            id="tier-dialog-title"
            class="text-lg font-semibold text-[rgb(var(--foreground-primary))]"
          >
            Customize tiers
          </p>
        </div>

        <div class="max-h-[65vh] space-y-2.5 overflow-y-auto px-5 py-4">
          <div
            :for={{tier, index} <- Enum.with_index(@tiers)}
            class="rounded-[8px] bg-[rgb(var(--surface-elevated))] p-2.5"
          >
            <div class="flex items-center gap-2">
              <div class="flex shrink-0 flex-col gap-1">
                <button
                  type="button"
                  phx-click="move_tier"
                  phx-value-id={tier.id}
                  phx-value-direction="up"
                  disabled={index == 0}
                  class="flex size-[17px] items-center justify-center rounded-[4px] text-[rgb(var(--foreground-tertiary))] transition hover:bg-white/4 hover:text-[rgb(var(--foreground-primary))] disabled:cursor-not-allowed disabled:opacity-30"
                  aria-label={"Move #{tier.label} tier up"}
                >
                  <.icon name={:chevron_up} class="size-3.5" />
                </button>
                <button
                  type="button"
                  phx-click="move_tier"
                  phx-value-id={tier.id}
                  phx-value-direction="down"
                  disabled={index == length(@tiers) - 1}
                  class="flex size-[17px] items-center justify-center rounded-[4px] text-[rgb(var(--foreground-tertiary))] transition hover:bg-white/4 hover:text-[rgb(var(--foreground-primary))] disabled:cursor-not-allowed disabled:opacity-30"
                  aria-label={"Move #{tier.label} tier down"}
                >
                  <.icon name={:chevron_down} class="size-3.5" />
                </button>
              </div>

              <details class="group relative shrink-0">
                <summary
                  class="flex size-9 cursor-pointer list-none items-center justify-center rounded-[8px] border border-[rgb(var(--border-divider))] transition-shadow hover:shadow-[0_0_0_2px_rgba(255,255,255,0.12)] [&::-webkit-details-marker]:hidden"
                  style={"background-color: #{tier.color}"}
                  aria-label={"Choose color for #{tier.label}"}
                >
                  <.icon
                    name={:check}
                    class="size-4 text-white drop-shadow-[0_1px_2px_rgba(0,0,0,0.85)]"
                  />
                </summary>
                <div class="absolute top-full left-0 z-90 mt-2 grid w-[194px] grid-cols-5 gap-1.5 rounded-[10px] border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-base))] p-2 shadow-2xl">
                  <button
                    :for={color <- @colors}
                    type="button"
                    phx-click="set_tier_color"
                    phx-value-id={tier.id}
                    phx-value-color={color}
                    class={[
                      "relative flex size-8 items-center justify-center rounded-[7px] border transition-shadow hover:border-white/35 hover:shadow-[0_0_0_2px_rgba(255,255,255,0.12)] active:brightness-95",
                      if(String.downcase(tier.color) == String.downcase(color),
                        do: "border-[rgb(var(--foreground-primary))]",
                        else: "border-white/10"
                      )
                    ]}
                    style={"background-color: #{color}"}
                    aria-label={"Use #{color} for #{tier.label}"}
                    aria-pressed={String.downcase(tier.color) == String.downcase(color)}
                  >
                    <.icon
                      :if={String.downcase(tier.color) == String.downcase(color)}
                      name={:check}
                      class="size-4 text-white drop-shadow-[0_1px_2px_rgba(0,0,0,0.85)]"
                    />
                  </button>
                </div>
              </details>

              <form phx-change="set_tier_label" class="min-w-0 flex-1">
                <input type="hidden" name="tier_id" value={tier.id} />
                <input
                  type="text"
                  name="label"
                  value={tier.label}
                  maxlength="24"
                  phx-debounce="300"
                  placeholder={default_tier_label(index)}
                  class="h-9 w-full rounded-[8px] border border-[rgb(var(--border-divider))] bg-[rgb(var(--text-field-bg))] px-3 text-sm text-[rgb(var(--foreground-primary))] placeholder:text-[rgb(var(--text-field-placeholder-text))] focus:border-[rgb(var(--text-field-border-focus))] focus:outline-none"
                />
              </form>

              <button
                type="button"
                phx-click="remove_tier"
                phx-value-id={tier.id}
                disabled={length(@tiers) <= 1}
                class="flex size-9 shrink-0 items-center justify-center rounded-[8px] text-[rgb(var(--foreground-tertiary))] transition hover:bg-white/4 hover:text-[rgb(var(--foreground-primary))] disabled:cursor-not-allowed disabled:opacity-40"
                aria-label={"Remove #{tier.label} tier"}
              >
                <.icon name={:trash} class="size-4" />
              </button>
            </div>
          </div>

          <button
            :if={@can_add_tier}
            type="button"
            phx-click="add_tier"
            class="flex h-10 w-full items-center justify-center gap-2 rounded-[8px] border border-dashed border-[rgb(var(--border-divider))] bg-transparent text-sm font-normal text-[rgb(var(--foreground-primary))] transition hover:bg-[rgb(var(--surface-elevated))]/80"
          >
            <.icon name={:plus} class="size-4" /> Add tier
          </button>
        </div>

        <div class="flex w-full items-center justify-end gap-2 px-5 pb-5">
          <button
            type="button"
            phx-click="close_tier_editor"
            class="h-10 rounded-[8px] bg-[rgb(var(--surface-elevated))] px-4 text-sm font-normal text-[rgb(var(--foreground-primary))] transition hover:bg-white/8"
          >
            Cancel
          </button>
          <button
            type="button"
            phx-click="save_tier_draft"
            class="h-10 rounded-[8px] bg-[rgb(var(--button-background-brand-default))] px-4 text-sm font-normal text-[rgb(var(--button-text-on-brand))] transition hover:bg-[rgb(var(--button-background-brand-hover))]"
          >
            Save
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :field, :any, required: true
  attr :class, :string, default: nil

  defp field_errors(assigns) do
    ~H"""
    <p
      :for={error <- field_error_messages(@field)}
      role="alert"
      class={["mt-1 text-xs text-[rgb(var(--foreground-error))]", @class]}
    >
      {error}
    </p>
    """
  end

  attr :items, :list, required: true
  attr :is_ranked, :boolean, default: false

  defp grid_surface(assigns) do
    ~H"""
    <div class={[
      "grid h-full grid-cols-4 gap-x-[5px] gap-y-[5px] pt-5 text-[rgb(var(--foreground-primary))] max-md:mt-5 sm:grid-cols-5 md:grid-cols-6 md:gap-2 md:max-lg:mt-6 lg:grid-cols-6",
      @is_ranked && "gap-y-1"
    ]}>
      <div
        :for={{item, index} <- Enum.with_index(@items)}
        class="group relative touch-pan-y select-none"
      >
        <div class="relative aspect-1/1.5 overflow-hidden">
          <.cover item={item} />
          <div class="absolute top-1 right-1 flex gap-1 opacity-100 transition md:opacity-0 md:group-hover:opacity-100">
            <button
              type="button"
              phx-click="move_item"
              phx-value-index={index}
              phx-value-direction="up"
              disabled={index == 0}
              class="flex size-7 items-center justify-center rounded-full bg-black/70 text-white transition hover:bg-black disabled:opacity-30"
              aria-label="Move earlier"
            >
              <.icon name={:chevron_up} class="size-4" />
            </button>
            <button
              type="button"
              phx-click="move_item"
              phx-value-index={index}
              phx-value-direction="down"
              disabled={index == length(@items) - 1}
              class="flex size-7 items-center justify-center rounded-full bg-black/70 text-white transition hover:bg-black disabled:opacity-30"
              aria-label="Move later"
            >
              <.icon name={:chevron_down} class="size-4" />
            </button>
            <button
              type="button"
              phx-click="remove_item"
              phx-value-id={item.id}
              class="flex size-7 items-center justify-center rounded-full bg-black/70 text-white transition hover:bg-black"
              aria-label={"Remove #{item.title}"}
            >
              <.icon name={:trash} class="size-3.5" />
            </button>
          </div>
        </div>
        <p :if={@is_ranked} class="mt-1 text-center text-xs text-[rgb(var(--foreground-secondary))]">
          {index + 1}
        </p>
      </div>
    </div>
    """
  end

  attr :items, :list, required: true
  attr :tiers, :list, required: true
  attr :is_ranked, :boolean, default: false

  defp tier_surface(assigns) do
    assigns =
      assign(assigns,
        unranked_items: Enum.filter(assigns.items, &is_nil(&1[:tier_id])),
        tiers: normalize_tiers_for_render(assigns.tiers)
      )

    ~H"""
    <div class="space-y-3 pt-5">
      <div
        :for={tier <- @tiers}
        class="rounded-[8px] border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-elevated))]"
      >
        <div class="flex min-h-14 gap-3 p-2">
          <div
            class="flex w-[104px] shrink-0 items-center justify-center rounded-[6px] px-2 text-sm font-semibold text-white max-sm:w-[56px]"
            style={"background-color: #{tier.color}"}
          >
            <span class="line-clamp-2 text-center wrap-break-word">{tier.label}</span>
          </div>
          <.tier_items items={items_for_tier(@items, tier.id)} is_ranked={@is_ranked} />
        </div>
      </div>

      <div class="rounded-[8px] border border-dashed border-[rgb(var(--border-divider))] bg-transparent">
        <div class="flex min-h-14 gap-3 p-2">
          <div class="flex w-[104px] shrink-0 items-center justify-center rounded-[6px] bg-[rgb(var(--surface-elevated))] px-2 text-center text-xs font-medium text-[rgb(var(--foreground-secondary))] max-sm:w-[56px]">
            Unranked
          </div>
          <.tier_items items={@unranked_items} is_ranked={@is_ranked} />
        </div>
      </div>
    </div>
    """
  end

  attr :items, :list, required: true
  attr :is_ranked, :boolean, default: false

  defp tier_items(assigns) do
    ~H"""
    <div class="min-w-0 flex-1">
      <div
        :if={@items == []}
        class="flex h-full min-h-20 items-center text-sm text-[rgb(var(--foreground-tertiary))]"
      >
        No VNs in this row
      </div>
      <div :if={@items != []} class="grid grid-cols-4 gap-2 sm:grid-cols-6 lg:grid-cols-8">
        <div :for={{item, index} <- Enum.with_index(@items)} class="group relative">
          <.cover item={item} />
          <button
            type="button"
            phx-click="remove_item"
            phx-value-id={item.id}
            class="absolute top-1 right-1 flex size-7 items-center justify-center rounded-full bg-black/70 text-white opacity-100 transition hover:bg-black md:opacity-0 md:group-hover:opacity-100"
            aria-label={"Remove #{item.title}"}
          >
            <.icon name={:trash} class="size-3.5" />
          </button>
          <p :if={@is_ranked} class="mt-1 text-center text-xs text-[rgb(var(--foreground-secondary))]">
            {index + 1}
          </p>
        </div>
      </div>
    </div>
    """
  end

  attr :item, :map, required: true

  defp cover(assigns) do
    assigns = assign(assigns, :nsfw_blur?, item_cover_needs_blur?(assigns.item))

    ~H"""
    <div class="aspect-1/1.5 overflow-hidden rounded-[2px] bg-[rgb(var(--surface-elevated))]">
      <img
        :if={image_url(@item)}
        src={image_url(@item)}
        alt={@item.title || "Visual novel cover"}
        class="size-full rounded-[2px] object-cover object-center"
        loading="lazy"
        data-nsfw-blur={if @nsfw_blur?, do: "1"}
        style={if @nsfw_blur?, do: "--nsfw-blur-size: 140;"}
      />
      <div
        :if={!image_url(@item)}
        class="flex size-full items-center justify-center rounded-[2px] border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-elevated))] p-2 text-center text-xs text-[rgb(var(--foreground-tertiary))]"
      >
        {fallback_title(@item)}
      </div>
    </div>
    """
  end

  attr :item, :map, required: true

  defp mobile_cover(assigns) do
    assigns = assign(assigns, :nsfw_blur?, item_cover_needs_blur?(assigns.item))

    ~H"""
    <div class="h-[84px] w-14 shrink-0 overflow-hidden rounded-md bg-[rgb(var(--surface-elevated))]">
      <img
        :if={image_url(@item)}
        src={image_url(@item)}
        alt={@item.title || "Visual novel cover"}
        class="size-full object-cover object-center"
        loading="lazy"
        data-nsfw-blur={if @nsfw_blur?, do: "1"}
        style={if @nsfw_blur?, do: "--nsfw-blur-size: 56;"}
      />
      <div
        :if={!image_url(@item)}
        class="flex size-full items-center justify-center text-[rgb(var(--foreground-tertiary))]"
        aria-hidden="true"
      >
        <Lucide.image class="size-5" aria-hidden />
      </div>
    </div>
    """
  end

  attr :name, :atom, required: true
  attr :class, :string, default: "size-4"

  def icon(%{name: :x} = assigns) do
    ~H"""
    <Lucide.x class={@class} aria-hidden />
    """
  end

  def icon(%{name: :check} = assigns) do
    ~H"""
    <Lucide.check class={@class} aria-hidden />
    """
  end

  def icon(%{name: :plus} = assigns) do
    ~H"""
    <Lucide.plus class={@class} aria-hidden />
    """
  end

  def icon(%{name: :trash} = assigns) do
    ~H"""
    <Lucide.trash_2 class={@class} aria-hidden />
    """
  end

  def icon(%{name: :globe} = assigns) do
    ~H"""
    <Lucide.globe class={@class} aria-hidden />
    """
  end

  def icon(%{name: :lock} = assigns) do
    ~H"""
    <Lucide.lock class={@class} aria-hidden />
    """
  end

  def icon(%{name: :lock_open} = assigns) do
    ~H"""
    <Lucide.lock_open class={@class} aria-hidden />
    """
  end

  def icon(%{name: :grid} = assigns) do
    ~H"""
    <Lucide.layout_grid class={@class} aria-hidden />
    """
  end

  def icon(%{name: :rows} = assigns) do
    ~H"""
    <Lucide.rows_3 class={@class} aria-hidden />
    """
  end

  def icon(%{name: :list} = assigns) do
    ~H"""
    <Lucide.list class={@class} aria-hidden />
    """
  end

  def icon(%{name: :list_ordered} = assigns) do
    ~H"""
    <Lucide.list_ordered class={@class} aria-hidden />
    """
  end

  def icon(%{name: :info} = assigns) do
    ~H"""
    <Lucide.info class={@class} aria-hidden />
    """
  end

  def icon(%{name: :search} = assigns) do
    ~H"""
    <.search_icon class={@class} aria-hidden />
    """
  end

  def icon(%{name: :chevron_up} = assigns) do
    ~H"""
    <Lucide.chevron_up class={@class} aria-hidden />
    """
  end

  def icon(%{name: :chevron_down} = assigns) do
    ~H"""
    <Lucide.chevron_down class={@class} aria-hidden />
    """
  end

  def icon(%{name: :warning} = assigns) do
    ~H"""
    <Lucide.triangle_alert class={@class} aria-hidden />
    """
  end

  def icon(%{name: :arrow_left} = assigns) do
    ~H"""
    <Lucide.arrow_left class={@class} aria-hidden />
    """
  end

  def icon(%{name: :settings} = assigns) do
    ~H"""
    <Lucide.sliders_horizontal class={@class} aria-hidden />
    """
  end

  def icon(%{name: :rotate_ccw} = assigns) do
    ~H"""
    <Lucide.rotate_ccw class={@class} aria-hidden />
    """
  end

  defp bool_value(values, key, default) do
    case Map.get(values, key, default) do
      value when value in [true, "true", "1", 1] -> true
      value when value in [false, "false", "0", 0] -> false
      _ -> default
    end
  end

  defp display_mode(values) do
    case Map.get(values, "display_mode", "grid") do
      "tier" -> "tier"
      :tier -> "tier"
      _ -> "grid"
    end
  end

  defp description_length(form) do
    form
    |> input_value(:description)
    |> to_string()
    |> String.length()
  end

  defp field_error_messages(field) do
    Enum.map(field.errors, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp image_url(item) do
    images = item[:images] || %{}

    item[:image_url] ||
      item[:imageUrl] ||
      images[:medium] ||
      images["medium"] ||
      images[:small] ||
      images["small"] ||
      images[:large] ||
      images["large"]
  end

  defp item_cover_needs_blur?(item) when is_map(item) do
    Map.get(item, :is_image_nsfw) == true or
      Map.get(item, "is_image_nsfw") == true or
      Map.get(item, :is_image_suggestive) == true or
      Map.get(item, "is_image_suggestive") == true
  end

  defp item_cover_needs_blur?(_), do: false

  defp fallback_title(%{title: title}) when is_binary(title) and title != "" do
    title
    |> String.trim()
    |> String.first()
    |> String.upcase()
  end

  defp fallback_title(_), do: "VN"

  defp producer_text(producers) when is_list(producers) do
    producers
    |> Enum.map(fn
      %{name: name} -> name
      %{"name" => name} -> name
      name when is_binary(name) -> name
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
  end

  defp producer_text(value) when is_binary(value), do: value
  defp producer_text(_), do: nil

  defp default_tier_label(index) do
    case Enum.at(default_tiers(), index) do
      %{label: label} -> label
      _ -> "Tier #{index + 1}"
    end
  end

  defp normalize_tiers_for_render([]), do: default_tiers()
  defp normalize_tiers_for_render(tiers), do: Enum.sort_by(tiers, & &1.position)

  defp items_for_tier(items, tier_id) do
    items
    |> Enum.filter(&(to_string(&1[:tier_id]) == to_string(tier_id)))
    |> Enum.sort_by(&(&1[:tier_position] || &1[:position] || 0))
  end

  defp default_tiers do
    [
      %{id: "tier-s", label: "S", color: "#f87171", position: 1},
      %{id: "tier-a", label: "A", color: "#fb923c", position: 2},
      %{id: "tier-b", label: "B", color: "#facc15", position: 3},
      %{id: "tier-c", label: "C", color: "#4ade80", position: 4},
      %{id: "tier-d", label: "D", color: "#60a5fa", position: 5}
    ]
  end
end
