defmodule KaguyaWeb.VNLive.Edit.Sections do
  @moduledoc false

  use KaguyaWeb, :html

  alias KaguyaWeb.VNLive.Edit.Form

  def title_section(assigns) do
    ~H"""
    <section id="vn-edit-title" class="scroll-mt-24 lg:scroll-mt-28">
      <div class="border-border-divider mb-4 flex items-center justify-between border-b pb-2">
        <h2 class="text-foreground-primary text-lg font-medium">Titles</h2>
        <button
          type="button"
          phx-click="add_title"
          class="rounded-[6px] border border-[rgb(var(--chip-border-default))] px-2.5 py-1 text-xs text-[rgb(var(--foreground-primary))] transition-colors hover:border-[rgb(var(--chip-border-hover))]"
        >
          Add title
        </button>
      </div>

      <div class="space-y-4">
        <div
          :for={{title, index} <- Enum.with_index(@form["titles"])}
          class="border-border-divider rounded-[8px] border p-3"
        >
          <div class="grid grid-cols-1 gap-3 md:grid-cols-[170px_minmax(0,1fr)]">
            <label class="flex flex-col gap-1.5 text-sm text-[rgb(var(--foreground-secondary))]">
              <span class="font-medium text-[rgb(var(--foreground-primary))]">Language</span>
              <select
                name={"vn[titles][#{index}][lang]"}
                class="bg-surface-elevated border-border-divider rounded-[6px] border px-3 py-2 text-[rgb(var(--foreground-primary))] outline-none"
              >
                <option
                  :for={{label, value} <- @language_options}
                  value={value}
                  selected={title["lang"] == value}
                >
                  {label}
                </option>
              </select>
            </label>

            <label class="flex flex-col gap-1.5 text-sm text-[rgb(var(--foreground-secondary))]">
              <span class="font-medium text-[rgb(var(--foreground-primary))]">
                Title
              </span>
              <input
                type="text"
                name={"vn[titles][#{index}][title]"}
                value={title["title"]}
                maxlength="1000"
                class="bg-surface-elevated border-border-divider rounded-[6px] border px-3 py-2 text-[rgb(var(--foreground-primary))] outline-none"
              />
            </label>
          </div>

          <div class="mt-3 grid grid-cols-1 gap-3 md:grid-cols-[minmax(0,1fr)_auto_auto]">
            <label class="flex flex-col gap-1.5 text-sm text-[rgb(var(--foreground-secondary))]">
              <span class="font-medium text-[rgb(var(--foreground-primary))]">
                Latin title
              </span>
              <input
                type="text"
                name={"vn[titles][#{index}][latin]"}
                value={title["latin"]}
                maxlength="1000"
                class="bg-surface-elevated border-border-divider rounded-[6px] border px-3 py-2 text-[rgb(var(--foreground-primary))] outline-none"
              />
            </label>

            <label class="flex items-end gap-2 pb-2 text-sm text-[rgb(var(--foreground-secondary))]">
              <input type="hidden" name={"vn[titles][#{index}][official]"} value="false" />
              <input
                type="checkbox"
                name={"vn[titles][#{index}][official]"}
                value="true"
                checked={title["official"]}
                class="bg-surface-elevated border-border-divider text-foreground-primary mt-0.5 size-4 rounded"
              />
              <span>Official</span>
            </label>

            <button
              type="button"
              phx-click="remove_title"
              phx-value-index={index}
              class="border-border-divider self-end rounded-[6px] border px-3 py-2 text-xs text-[rgb(var(--foreground-secondary))] transition-colors hover:text-[rgb(var(--foreground-primary))]"
            >
              Remove
            </button>
          </div>
        </div>
      </div>
    </section>
    """
  end

  def general_section(assigns) do
    ~H"""
    <section id="vn-edit-general" class="scroll-mt-24 lg:scroll-mt-28">
      <h2 class="border-border-divider text-foreground-primary mb-6 border-b pb-2 text-lg font-medium">
        General
      </h2>

      <div class="grid grid-cols-1 gap-4 md:grid-cols-[170px_minmax(0,1fr)] md:items-start">
        <label class="contents">
          <span class="pt-2 text-sm font-medium text-[rgb(var(--foreground-primary))]">
            Description
          </span>
          <textarea
            name="vn[description]"
            rows="10"
            maxlength="5000"
            class="bg-surface-elevated border-border-divider min-h-[220px] rounded-[6px] border px-3 py-2 text-[rgb(var(--foreground-primary))] outline-none"
          ><%= @form["description"] %></textarea>
        </label>

        <label class="contents">
          <span class="pt-2 text-sm font-medium text-[rgb(var(--foreground-primary))]">
            Aliases
          </span>
          <textarea
            name="vn[aliases]"
            rows="4"
            maxlength="5000"
            placeholder="One alias per line"
            class="bg-surface-elevated border-border-divider min-h-[96px] rounded-[6px] border px-3 py-2 text-[rgb(var(--foreground-primary))] outline-none"
          ><%= @form["aliases"] %></textarea>
        </label>

        <label class="contents">
          <span class="pt-2 text-sm font-medium text-[rgb(var(--foreground-primary))]">
            Development status
          </span>
          <select
            name="vn[development_status]"
            class="bg-surface-elevated border-border-divider h-10 rounded-[6px] border px-3 py-2 text-[rgb(var(--foreground-primary))] outline-none md:max-w-[220px]"
          >
            <option
              :for={{label, value} <- @development_status_options}
              value={value}
              selected={@form["development_status"] == value}
            >
              {label}
            </option>
          </select>
        </label>

        <label class="contents">
          <span class="pt-2 text-sm font-medium text-[rgb(var(--foreground-primary))]">
            Length
          </span>
          <select
            name="vn[length_category]"
            class="bg-surface-elevated border-border-divider h-10 rounded-[6px] border px-3 py-2 text-[rgb(var(--foreground-primary))] outline-none md:max-w-[220px]"
          >
            <option
              :for={{label, value} <- @length_options}
              value={value}
              selected={@form["length_category"] == value}
            >
              {label}
            </option>
          </select>
        </label>

        <label class="contents">
          <span class="pt-2 text-sm font-medium text-[rgb(var(--foreground-primary))]">
            Original language
          </span>
          <select
            name="vn[original_language]"
            class="bg-surface-elevated border-border-divider h-10 rounded-[6px] border px-3 py-2 text-[rgb(var(--foreground-primary))] outline-none md:max-w-[220px]"
          >
            <option
              :for={{label, value} <- @language_options}
              value={value}
              selected={@form["original_language"] == value}
            >
              {label}
            </option>
          </select>
        </label>

        <label class="contents">
          <span class="pt-2 text-sm font-medium text-[rgb(var(--foreground-primary))]">
            Release date
          </span>
          <input
            type="date"
            name="vn[release_date]"
            value={@form["release_date"]}
            class="bg-surface-elevated border-border-divider h-10 rounded-[6px] border px-3 py-2 text-[rgb(var(--foreground-primary))] outline-none md:max-w-[220px]"
          />
        </label>

        <label class="contents">
          <span class="pt-2 text-sm font-medium text-[rgb(var(--foreground-primary))]">
            Minimum age
          </span>
          <input
            type="number"
            min="0"
            max="99"
            name="vn[min_age]"
            value={@form["min_age"]}
            class="bg-surface-elevated border-border-divider h-10 rounded-[6px] border px-3 py-2 text-[rgb(var(--foreground-primary))] outline-none md:max-w-[220px]"
          />
        </label>

        <label class="contents">
          <span class="pt-2 text-sm font-medium text-[rgb(var(--foreground-primary))]">
            Category
          </span>
          <select
            name="vn[title_category]"
            class="bg-surface-elevated border-border-divider h-10 rounded-[6px] border px-3 py-2 text-[rgb(var(--foreground-primary))] outline-none md:max-w-[220px]"
          >
            <option
              :for={{label, value} <- @title_category_options}
              value={value}
              selected={@form["title_category"] == value}
            >
              {label}
            </option>
          </select>
        </label>

        <div class="contents">
          <span class="pt-2 text-sm font-medium text-[rgb(var(--foreground-primary))]">
            Flags
          </span>
          <div class="flex flex-col gap-3 pt-1">
            <label class="flex items-start gap-2 text-sm text-[rgb(var(--foreground-secondary))]">
              <input type="hidden" name="vn[has_ero]" value="false" />
              <input
                type="checkbox"
                name="vn[has_ero]"
                value="true"
                checked={@form["has_ero"]}
                class="bg-surface-elevated border-border-divider text-foreground-primary mt-0.5 size-4 rounded"
              />
              <span>Has erotic content</span>
            </label>

            <label class="flex items-start gap-2 text-sm text-[rgb(var(--foreground-secondary))]">
              <input type="hidden" name="vn[is_avn]" value="false" />
              <input
                type="checkbox"
                name="vn[is_avn]"
                value="true"
                checked={@form["is_avn"]}
                class="bg-surface-elevated border-border-divider text-foreground-primary mt-0.5 size-4 rounded"
              />
              <span>Western adult VN scene</span>
            </label>
          </div>
        </div>
      </div>
    </section>
    """
  end

  def relations_section(assigns) do
    ~H"""
    <section id="vn-edit-relations" class="scroll-mt-24 lg:scroll-mt-28">
      <div class="border-border-divider mb-6 border-b pb-2">
        <h2 class="text-foreground-primary text-lg font-medium">Relations</h2>
      </div>

      <p
        :if={Form.visible_relations(@form) == []}
        class="text-foreground-tertiary text-style-captionRegular mb-4"
      >
        No related visual novels yet. Search below to add one.
      </p>

      <div :if={Form.visible_relations(@form) != []} class="mb-5 flex flex-col gap-1">
        <div
          :for={{relation, index} <- Enum.with_index(@form["relations"])}
          :if={!relation["removed"]}
          class="group flex items-center gap-3 py-1.5"
        >
          <button
            type="button"
            phx-click="remove_relation"
            phx-value-index={index}
            class="hover:text-semantic-error text-foreground-tertiary shrink-0 p-1 transition-colors"
            aria-label="Remove relation"
          >
            <span aria-hidden="true">×</span>
          </button>

          <.link
            navigate={"/vn/#{relation["related_vn_slug"]}"}
            class="hover:text-text-link-hover text-style-body2Regular text-text-link-default min-w-0 flex-1 truncate"
          >
            {relation["related_vn_title"]}
          </.link>

          <select
            name={"vn[relations][#{index}][relation_type]"}
            class="bg-surface-elevated border-border-divider h-10 w-[180px] shrink-0 rounded-[6px] border px-3 py-2 text-[rgb(var(--foreground-primary))] outline-none"
          >
            <option
              :for={{label, value} <- @relation_type_options}
              value={value}
              selected={relation["relation_type"] == value}
            >
              {label}
            </option>
          </select>

          <label class="text-foreground-secondary text-style-captionRegular flex shrink-0 cursor-pointer items-center gap-2">
            <input
              type="hidden"
              name={"vn[relations][#{index}][is_official]"}
              value="false"
            />
            <input
              type="checkbox"
              name={"vn[relations][#{index}][is_official]"}
              value="true"
              checked={relation["is_official"]}
              class="bg-surface-elevated border-border-divider text-foreground-primary size-4 rounded"
            />
            <span>Official</span>
          </label>

          <input
            type="hidden"
            name={"vn[relations][#{index}][related_vn_id]"}
            value={relation["related_vn_id"]}
          />
          <input
            type="hidden"
            name={"vn[relations][#{index}][related_vn_slug]"}
            value={relation["related_vn_slug"]}
          />
          <input
            type="hidden"
            name={"vn[relations][#{index}][related_vn_title]"}
            value={relation["related_vn_title"]}
          />
        </div>
      </div>

      <div class="space-y-3">
        <label class="flex flex-col gap-1.5 text-sm text-[rgb(var(--foreground-secondary))]">
          <span class="font-medium text-[rgb(var(--foreground-primary))]">
            Add related visual novel
          </span>
          <input
            id="vn-relation-search"
            type="text"
            name="relation_query"
            value={@relation_query}
            phx-hook="RelationSearch"
            phx-debounce="300"
            placeholder="Search by title"
            class="bg-surface-elevated border-border-divider h-10 rounded-[6px] border px-3 py-2 text-[rgb(var(--foreground-primary))] outline-none"
          />
        </label>

        <div :if={@relation_results != []} class="border-border-divider rounded-[8px] border">
          <button
            :for={result <- @relation_results}
            type="button"
            phx-click="add_relation_result"
            phx-value-id={result.id}
            phx-value-slug={result.slug}
            phx-value-title={result.title}
            class="border-border-divider/60 hover:bg-surface-menu-item-hover/20 flex w-full items-center justify-between gap-3 border-b px-3 py-2 text-left last:border-b-0"
          >
            <span class="text-foreground-primary truncate text-sm">{result.title}</span>
            <span class="text-foreground-tertiary truncate text-xs">/vn/{result.slug}</span>
          </button>
        </div>
      </div>
    </section>
    """
  end

  def screenshots_section(assigns) do
    ~H"""
    <section id="vn-edit-screenshots" class="scroll-mt-24 lg:scroll-mt-28">
      <div class="border-border-divider mb-6 flex items-center justify-between border-b pb-2">
        <h2 class="text-foreground-primary text-lg font-medium">Screenshots</h2>
        <label
          for={@uploads.new_screenshots.ref}
          class="hover:bg-surface-elevated cursor-pointer rounded-[6px] px-2.5 py-1 text-xs text-[rgb(var(--foreground-primary))] transition-colors"
        >
          Add
        </label>
      </div>

      <p :if={Form.visible_screenshots(@form) == []} class="text-foreground-tertiary text-sm">
        No screenshots yet.
      </p>

      <div
        :if={@uploads.new_screenshots.entries != []}
        class="mb-6 grid grid-cols-[repeat(auto-fill,minmax(220px,1fr))] gap-x-5 gap-y-6"
      >
        <div :for={entry <- @uploads.new_screenshots.entries} class="flex flex-col gap-2.5">
          <div class="group/thumb relative">
            <div class="bg-surface-elevated overflow-hidden rounded-md">
              <.live_img_preview
                entry={entry}
                class="aspect-video w-full object-cover transition-opacity"
              />
            </div>
            <button
              type="button"
              phx-click="cancel_upload"
              phx-value-upload="new_screenshots"
              phx-value-ref={entry.ref}
              class="absolute -top-1.5 -right-1.5 z-10 flex size-6 items-center justify-center rounded-full bg-black/70 opacity-0 transition-opacity duration-200 group-hover/thumb:opacity-100"
              aria-label="Remove screenshot upload"
            >
              <span aria-hidden="true" class="text-sm text-white">×</span>
            </button>
          </div>

          <div class="flex items-center justify-between gap-3">
            <span class="text-foreground-secondary truncate text-xs">
              {entry.client_name}
            </span>
            <span class="text-foreground-tertiary text-xs">{entry.progress}%</span>
          </div>

          <p
            :for={error <- upload_errors(@uploads.new_screenshots, entry)}
            class="text-semantic-error text-xs"
          >
            {upload_error_message(error)}
          </p>
        </div>
      </div>

      <div
        :if={Form.visible_screenshots(@form) != []}
        class="grid grid-cols-[repeat(auto-fill,minmax(220px,1fr))] gap-x-5 gap-y-6"
      >
        <div
          :for={{entry, index} <- Enum.with_index(@form["screenshots"])}
          :if={!entry["removed"]}
          class="flex flex-col gap-2.5"
        >
          <div class="group/thumb relative">
            <div class="bg-surface-elevated overflow-hidden rounded-md transition-transform duration-300 ease-[cubic-bezier(0.33,1,0.68,1)] will-change-transform group-hover/thumb:scale-[1.025]">
              <img
                src={entry["thumbnail_url"]}
                alt=""
                class="aspect-video w-full object-cover"
                loading="lazy"
                decoding="async"
              />
            </div>
            <button
              type="button"
              phx-click="remove_screenshot"
              phx-value-id={entry["id"]}
              class="absolute -top-1.5 -right-1.5 z-10 flex size-6 items-center justify-center rounded-full bg-black/70 opacity-0 transition-opacity duration-200 group-hover/thumb:opacity-100"
              aria-label="Remove screenshot"
            >
              <span aria-hidden="true" class="text-sm text-white">×</span>
            </button>
          </div>

          <div class="flex items-center justify-between gap-3">
            <div class="flex items-center gap-4">
              <label class="text-foreground-tertiary flex cursor-pointer items-center gap-1.5 text-xs">
                <input
                  type="hidden"
                  name={"vn[screenshots][#{index}][is_nsfw]"}
                  value="false"
                />
                <input
                  type="checkbox"
                  name={"vn[screenshots][#{index}][is_nsfw]"}
                  value="true"
                  checked={entry["is_nsfw"]}
                  class="bg-surface-elevated border-border-divider text-foreground-primary size-4 rounded"
                />
                <span>NSFW</span>
              </label>

              <label
                :if={!@form["is_avn"]}
                class="text-foreground-tertiary flex cursor-pointer items-center gap-1.5 text-xs"
              >
                <input
                  type="hidden"
                  name={"vn[screenshots][#{index}][is_brutal]"}
                  value="false"
                />
                <input
                  type="checkbox"
                  name={"vn[screenshots][#{index}][is_brutal]"}
                  value="true"
                  checked={entry["is_brutal"]}
                  class="bg-surface-elevated border-border-divider text-foreground-primary size-4 rounded"
                />
                <span>Brutal</span>
              </label>
            </div>
          </div>

          <input type="hidden" name={"vn[screenshots][#{index}][id]"} value={entry["id"]} />
          <input
            type="hidden"
            name={"vn[screenshots][#{index}][thumbnail_url]"}
            value={entry["thumbnail_url"]}
          />
        </div>
      </div>
    </section>
    """
  end

  def covers_section(assigns) do
    ~H"""
    <section id="vn-edit-covers" class="scroll-mt-24 lg:scroll-mt-28">
      <div class="border-border-divider mb-6 flex items-center justify-between border-b pb-2">
        <h2 class="text-foreground-primary text-lg font-medium">Covers</h2>
        <label
          for={@uploads.new_covers.ref}
          class="hover:bg-surface-elevated cursor-pointer rounded-[6px] px-2.5 py-1 text-xs text-[rgb(var(--foreground-primary))] transition-colors"
        >
          Add
        </label>
      </div>

      <p :if={Form.visible_covers(@form) == []} class="text-foreground-tertiary text-sm">
        No covers yet.
      </p>

      <div
        :if={@uploads.new_covers.entries != []}
        class="mb-6 grid grid-cols-[repeat(auto-fill,minmax(140px,1fr))] gap-x-5 gap-y-6"
      >
        <div :for={entry <- @uploads.new_covers.entries} class="flex flex-col gap-2.5">
          <div class="group/fav relative">
            <div class="bg-surface-elevated aspect-2/3 overflow-hidden rounded-md">
              <.live_img_preview
                entry={entry}
                class="size-full object-cover transition-opacity"
              />
            </div>
            <button
              type="button"
              phx-click="cancel_upload"
              phx-value-upload="new_covers"
              phx-value-ref={entry.ref}
              class="absolute -top-1.5 -right-1.5 z-10 flex size-6 items-center justify-center rounded-full bg-black/70 opacity-0 transition-opacity duration-200 group-hover/fav:opacity-100"
              aria-label="Remove cover upload"
            >
              <span aria-hidden="true" class="text-sm text-white">×</span>
            </button>
          </div>

          <div class="flex items-center justify-between gap-3">
            <span class="text-foreground-secondary truncate text-xs">
              {entry.client_name}
            </span>
            <span class="text-foreground-tertiary text-xs">{entry.progress}%</span>
          </div>

          <p
            :for={error <- upload_errors(@uploads.new_covers, entry)}
            class="text-semantic-error text-xs"
          >
            {upload_error_message(error)}
          </p>
        </div>
      </div>

      <div
        :if={Form.visible_covers(@form) != []}
        class="grid grid-cols-[repeat(auto-fill,minmax(140px,1fr))] gap-x-5 gap-y-6"
      >
        <div
          :for={{cover, index} <- Enum.with_index(@form["covers"])}
          :if={!cover["removed"]}
          class="flex flex-col gap-2.5"
        >
          <div class="group/fav relative">
            <div class="bg-surface-elevated aspect-2/3 overflow-hidden rounded-md transition-transform duration-300 ease-[cubic-bezier(0.33,1,0.68,1)] will-change-transform group-hover/fav:scale-[1.025]">
              <img
                src={cover["thumbnail_url"]}
                alt=""
                class="size-full object-cover"
                loading="lazy"
                decoding="async"
              />
            </div>
            <button
              type="button"
              phx-click="remove_cover"
              phx-value-id={cover["id"]}
              class="absolute -top-1.5 -right-1.5 z-10 flex size-6 items-center justify-center rounded-full bg-black/70 opacity-0 transition-opacity duration-200 group-hover/fav:opacity-100"
              aria-label="Remove cover"
            >
              <span aria-hidden="true" class="text-sm text-white">×</span>
            </button>
          </div>

          <div class="flex items-center justify-between gap-2">
            <label class="text-foreground-tertiary flex cursor-pointer items-center gap-1.5 text-xs">
              <input
                type="hidden"
                name={"vn[covers][#{index}][is_image_nsfw]"}
                value="false"
              />
              <input
                type="checkbox"
                name={"vn[covers][#{index}][is_image_nsfw]"}
                value="true"
                checked={cover["is_image_nsfw"]}
                class="bg-surface-elevated border-border-divider text-foreground-primary size-4 rounded"
              />
              <span>NSFW</span>
            </label>

            <label class="text-foreground-tertiary flex cursor-pointer items-center gap-1.5 text-xs">
              <input
                type="radio"
                name="vn[primary_cover_id]"
                value={cover["id"]}
                checked={@form["primary_cover_id"] == cover["id"]}
                class="bg-surface-elevated border-border-divider text-foreground-primary size-4"
              />
              <span>Primary</span>
            </label>
          </div>

          <input type="hidden" name={"vn[covers][#{index}][id]"} value={cover["id"]} />
          <input
            type="hidden"
            name={"vn[covers][#{index}][thumbnail_url]"}
            value={cover["thumbnail_url"]}
          />
        </div>
      </div>
    </section>
    """
  end

  defp upload_error_message(:too_large), do: "Image must be under 10 MB."
  defp upload_error_message(:not_accepted), do: "Image must be JPEG, PNG, or WebP."
  defp upload_error_message(:too_many_files), do: "Too many files selected."
  defp upload_error_message(error), do: Phoenix.Naming.humanize(to_string(error))
end
