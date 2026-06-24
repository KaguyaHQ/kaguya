defmodule KaguyaWeb.VN.Panels.Releases do
  @moduledoc """
  Releases tab: edition + patch rows, with language/platform filters and
  a "Show more" collapse past nine entries. Language and platform code
  tables live here because they only matter inside this view; if a
  second caller ever needs them, promote them to the domain layer.

  The `chip_color/1` palette keeps a consistent visual scan across release rows.
  """

  use KaguyaWeb, :html

  import KaguyaWeb.VN.PanelHelpers, only: [show_more_button_class: 1]

  attr :items, :list, required: true
  attr :filters, :map, required: true
  attr :filter_options, :map, default: %{languages: [], platforms: []}
  attr :mobile, :boolean, default: false

  def panel(assigns) do
    languages =
      assigns.filter_options
      |> Map.get(:languages, [])
      |> normalize_filter_options(assigns.items, :languages)

    platforms =
      assigns.filter_options
      |> Map.get(:platforms, [])
      |> normalize_filter_options(assigns.items, :platforms)

    filters = normalize_release_filter_values(assigns.filters, languages, platforms)
    filtered_items = filter_releases(assigns.items, filters)
    {editions, patches} = split_releases(filtered_items)
    total_count = length(editions) + length(patches)
    collapse? = total_count > 9
    visible_editions = Enum.take(editions, 9)
    remaining_slots = max(9 - length(visible_editions), 0)
    visible_patches = if collapse?, do: Enum.take(patches, remaining_slots), else: patches
    hidden_count = total_count - length(visible_editions) - length(visible_patches)

    assigns =
      assigns
      |> assign(:languages, languages)
      |> assign(:platforms, platforms)
      |> assign(:filters, filters)
      |> assign(:editions, editions)
      |> assign(:patches, patches)
      |> assign(:visible_editions, visible_editions)
      |> assign(:visible_patches, visible_patches)
      |> assign(:hidden_count, hidden_count)
      |> assign(:only_patches?, editions == [] and patches != [])
      |> assign(
        :form_id,
        if(assigns.mobile, do: "mobile-release-filters", else: "desktop-release-filters")
      )

    ~H"""
    <div class="flex flex-col gap-4">
      <div :if={@languages != [] or @platforms != []} class="flex items-center justify-between gap-3">
        <span class="text-[11px] font-medium tracking-wider text-[rgb(var(--foreground-secondary))] uppercase">
          {if @only_patches?, do: "Patches", else: "Editions"}
        </span>

        <.form
          for={%{}}
          as={:release_filters}
          id={@form_id}
          phx-change="set_release_filters"
          phx-hook="ReleaseFilters"
          class="ml-auto flex items-center gap-2"
        >
          <select
            :if={@languages != []}
            name="release_filters[language]"
            class="h-7 w-auto rounded-lg border border-[rgb(var(--border-divider))]/60 bg-transparent px-2.5 text-xs text-[rgb(var(--foreground-secondary))] transition-colors hover:border-[rgb(var(--border-divider))] focus:ring-0 focus:ring-offset-0 focus:outline-none"
          >
            <option :for={code <- @languages} value={code} selected={@filters.language == code}>
              {language_name(code)}
            </option>
          </select>

          <select
            :if={@platforms != []}
            name="release_filters[platform]"
            class="h-7 w-auto rounded-lg border border-[rgb(var(--border-divider))]/60 bg-transparent px-2.5 text-xs text-[rgb(var(--foreground-secondary))] transition-colors hover:border-[rgb(var(--border-divider))] focus:ring-0 focus:ring-offset-0 focus:outline-none"
          >
            <option :for={code <- @platforms} value={code} selected={@filters.platform == code}>
              {platform_name(code)}
            </option>
          </select>
        </.form>
      </div>

      <p
        :if={@editions == [] and @patches == []}
        class="py-4 text-sm text-[rgb(var(--foreground-secondary))]"
      >
        No releases found. Try selecting a different language or platform.
      </p>

      <div :if={@editions != [] or @patches != []} class="flex flex-col">
        <.release_row :for={release <- @visible_editions} release={release} />

        <div :if={@visible_patches != [] and @visible_editions != []} class="pt-5 pb-3">
          <span class="text-[11px] font-medium tracking-wider text-[rgb(var(--foreground-secondary))] uppercase">
            Patches
          </span>
        </div>

        <.release_row :for={release <- @visible_patches} release={release} />

        <details :if={@hidden_count > 0} class="group/release-more">
          <summary class={show_more_button_class(["mt-2", "group-open/release-more:hidden"])}>
            Show More
          </summary>
          <.release_row
            :for={release <- Enum.drop(@editions, length(@visible_editions))}
            release={release}
          />
          <div
            :if={
              Enum.drop(@patches, length(@visible_patches)) != [] and @visible_editions != [] and
                @visible_patches == []
            }
            class="pt-5 pb-3"
          >
            <span class="text-[11px] font-medium tracking-wider text-[rgb(var(--foreground-secondary))] uppercase">
              Patches
            </span>
          </div>
          <.release_row
            :for={release <- Enum.drop(@patches, length(@visible_patches))}
            release={release}
          />
        </details>
      </div>
    </div>
    """
  end

  def skeleton(assigns) do
    ~H"""
    <div class="flex flex-col gap-3">
      <div
        :for={_ <- 1..4}
        class="flex items-center justify-between gap-3 border-b border-[rgb(var(--border-divider))] py-3 last:border-b-0"
      >
        <div class="h-3 w-1/2 animate-pulse rounded-full bg-[rgb(var(--surface-banner))]/40"></div>
        <div class="h-3 w-16 animate-pulse rounded-full bg-[rgb(var(--surface-banner))]/30"></div>
      </div>
    </div>
    """
  end

  attr :release, :map, required: true

  defp release_row(assigns) do
    assigns =
      assigns
      |> assign(:title, Map.get(assigns.release, :title) || "Untitled release")
      |> assign(:release_date, Map.get(assigns.release, :release_date) || "—")
      |> assign(:flags, Map.get(assigns.release, :flags, []))
      |> assign(
        :extlinks,
        (Map.get(assigns.release, :extlinks, []) || []) |> Enum.filter(&extlink_url/1)
      )
      |> assign(:notes, Map.get(assigns.release, :notes))

    ~H"""
    <div class="grid grid-cols-[1fr_auto] items-center gap-x-3 gap-y-1 border-b border-[rgb(var(--border-divider))] py-2.5 last:border-b-0 lg:grid-cols-[1fr_auto_auto_auto] lg:gap-x-4">
      <div class="min-w-0">
        <p class="truncate text-[13px] leading-[18px] text-[rgb(var(--foreground-secondary))]">
          {@title}
        </p>
      </div>

      <div :if={@flags != []} class="hidden flex-wrap items-center gap-1 lg:flex">
        <span
          :for={flag <- @flags}
          class={[
            "inline-flex items-center rounded-full px-2 py-0.5 text-[10px] tracking-wider uppercase",
            chip_color(flag)
          ]}
        >
          {flag}
        </span>
      </div>

      <div
        :if={@extlinks != []}
        class="hidden max-w-[260px] flex-wrap items-center justify-center gap-1.5 lg:flex"
      >
        <.link
          :for={link <- @extlinks}
          href={extlink_url(link)}
          target="_blank"
          rel="noopener noreferrer"
          class="inline-flex items-center gap-1 rounded-full border border-[rgb(var(--foreground-primary))]/20 px-2 py-0.5 text-[11px] whitespace-nowrap text-[rgb(var(--foreground-primary))] transition-colors hover:border-[rgb(var(--foreground-primary))]/40"
        >
          {extlink_label(link)}
        </.link>
      </div>

      <p class="text-right text-[11px] whitespace-nowrap text-[rgb(var(--foreground-tertiary))]">
        {@release_date}
      </p>

      <div
        :if={@flags != [] or @extlinks != [] or @notes}
        class="col-span-2 -mt-1 flex flex-wrap items-center gap-1 lg:hidden"
      >
        <span
          :for={flag <- @flags}
          class={[
            "inline-flex items-center rounded-full px-1.5 py-px text-[10px] tracking-wider uppercase",
            chip_color(flag)
          ]}
        >
          {flag}
        </span>
        <.link
          :for={link <- @extlinks}
          href={extlink_url(link)}
          target="_blank"
          rel="noopener noreferrer"
          class="inline-flex items-center gap-1 rounded-full border border-[rgb(var(--foreground-primary))]/20 px-2 py-0.5 text-[11px] text-[rgb(var(--foreground-primary))]"
        >
          {extlink_label(link)}
        </.link>
        <details :if={@notes} class="relative">
          <summary class="cursor-pointer list-none rounded-full border border-[rgb(var(--foreground-primary))]/20 px-2 py-0.5 text-[11px] text-[rgb(var(--foreground-primary))]">
            Notes
          </summary>
          <div class="absolute right-0 z-20 mt-1 w-64 rounded-[6px] border border-[rgb(var(--border-divider))] bg-[rgb(var(--surface-elevated))] p-3 text-xs/5 text-[rgb(var(--foreground-secondary))] shadow-xl">
            {@notes}
          </div>
        </details>
      </div>
      <details :if={@notes} class="col-span-2 hidden lg:col-start-1 lg:block">
        <summary class="cursor-pointer list-none text-[11px] text-[rgb(var(--foreground-tertiary))] underline-offset-2 transition hover:text-[rgb(var(--foreground-primary))] hover:underline">
          Notes
        </summary>
        <p class="mt-1 max-w-[56ch] text-xs/5 text-[rgb(var(--foreground-secondary))]">
          {@notes}
        </p>
      </details>
    </div>
    """
  end

  defp release_filter_options(items, key) do
    items
    |> Enum.flat_map(&release_codes(&1, key))
    |> Enum.uniq()
    |> sort_release_codes(key)
  end

  defp normalize_filter_options([], items, key), do: release_filter_options(items, key)

  defp normalize_filter_options(options, _items, key) when is_list(options),
    do: options |> Enum.uniq() |> sort_release_codes(key)

  defp release_codes(release, :platforms) do
    Map.get(release, :platforms) || Map.get(release, :platform_labels) || []
  end

  defp release_codes(release, key), do: Map.get(release, key) || []

  defp sort_release_codes(codes, :platforms), do: Enum.sort_by(codes, &platform_rank/1)
  defp sort_release_codes(codes, _key), do: Enum.sort(codes)

  defp normalize_release_filter_values(filters, languages, platforms) do
    %{
      language: preferred_release_filter(filters[:language], languages, "en"),
      platform: preferred_release_filter(filters[:platform], platforms, "win")
    }
  end

  defp preferred_release_filter(current, available, preferred) do
    cond do
      current in available -> current
      preferred in available -> preferred
      available != [] -> hd(available)
      true -> nil
    end
  end

  defp filter_releases(items, filters) do
    Enum.filter(items, fn release ->
      filter_matches?(release_codes(release, :languages), filters.language) and
        filter_matches?(release_codes(release, :platforms), filters.platform)
    end)
  end

  defp filter_matches?(_values, nil), do: true
  defp filter_matches?(values, selected), do: selected in (values || [])

  defp split_releases(items) do
    items
    |> Enum.sort_by(&release_sort_key/1)
    |> Enum.split_with(&(not Map.get(&1, :patch, false)))
  end

  defp release_sort_key(release) do
    {release_type_rank(Map.get(release, :release_type)),
     release_date_sort(Map.get(release, :release_date)), Map.get(release, :title) || ""}
  end

  defp release_type_rank(nil), do: 0
  defp release_type_rank("complete"), do: 0
  defp release_type_rank("partial"), do: 1
  defp release_type_rank(_), do: 2

  defp release_date_sort(nil), do: 0

  defp release_date_sort(date) do
    date
    |> String.replace("/", "-")
    |> Date.from_iso8601()
    |> case do
      {:ok, parsed} -> -Date.to_gregorian_days(parsed)
      _ -> 0
    end
  end

  defp language_name("en"), do: "English"
  defp language_name("ja"), do: "Japanese"
  defp language_name("zh"), do: "Chinese"
  defp language_name("ko"), do: "Korean"
  defp language_name("es"), do: "Spanish"
  defp language_name("fr"), do: "French"
  defp language_name("de"), do: "German"
  defp language_name("it"), do: "Italian"
  defp language_name("pt-br"), do: "Portuguese"
  defp language_name(code) when is_binary(code), do: String.upcase(code)
  defp language_name(_), do: "Language"

  defp platform_name("win"), do: "Windows"
  defp platform_name("mac"), do: "macOS"
  defp platform_name("lin"), do: "Linux"
  defp platform_name("and"), do: "Android"
  defp platform_name("ios"), do: "iOS"
  defp platform_name("web"), do: "Web"
  defp platform_name("swi"), do: "Switch"
  defp platform_name("sw2"), do: "Switch 2"
  defp platform_name("ps5"), do: "PS5"
  defp platform_name("ps4"), do: "PS4"
  defp platform_name("ps3"), do: "PS3"
  defp platform_name("ps2"), do: "PS2"
  defp platform_name("ps1"), do: "PS1"
  defp platform_name("psv"), do: "Vita"
  defp platform_name("psp"), do: "PSP"
  defp platform_name("xxs"), do: "Xbox X|S"
  defp platform_name("xbo"), do: "Xbox One"
  defp platform_name("x36"), do: "Xbox 360"
  defp platform_name("nds"), do: "NDS"
  defp platform_name("n3d"), do: "3DS"
  defp platform_name("wii"), do: "Wii"
  defp platform_name("wiu"), do: "Wii U"
  defp platform_name(code) when is_binary(code), do: String.upcase(code)
  defp platform_name(_), do: "Platform"

  defp platform_rank(code) do
    [
      "win",
      "mac",
      "lin",
      "and",
      "ios",
      "web",
      "swi",
      "sw2",
      "ps5",
      "ps4",
      "ps3",
      "ps2",
      "ps1",
      "psv",
      "psp",
      "xxs",
      "xbo",
      "x36",
      "nds",
      "n3d",
      "wii",
      "wiu"
    ]
    |> Enum.find_index(&(&1 == code))
    |> case do
      nil -> 999
      rank -> rank
    end
  end

  defp chip_color("official"), do: "text-[#c4a96a] bg-[#c4a96a]/[0.09]"
  defp chip_color("unofficial"), do: "text-[#9a8bbe] bg-[#9a8bbe]/[0.09]"
  defp chip_color("partial"), do: "text-[#c48a8a] bg-[#c48a8a]/[0.09]"
  defp chip_color("trial"), do: "text-[#c48a8a] bg-[#c48a8a]/[0.09]"
  defp chip_color("free"), do: "text-[#8aab7c] bg-[#8aab7c]/[0.09]"
  defp chip_color("paid"), do: "text-[#c4956a] bg-[#c4956a]/[0.09]"
  defp chip_color("uncensored"), do: "text-[#7db5a8] bg-[#7db5a8]/[0.09]"

  defp chip_color(label) do
    cond do
      String.ends_with?(label, "+") -> "text-[#d4a574] bg-[#d4a574]/[0.09]"
      String.contains?(label, "voiced") -> "text-[#7db5a8] bg-[#7db5a8]/[0.09]"
      true -> "text-[#8a9bb5] bg-[#8a9bb5]/[0.09]"
    end
  end

  defp extlink_label(%{site: "website", url: url}) when is_binary(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) -> String.replace_prefix(host, "www.", "")
      _ -> url
    end
  end

  defp extlink_label(%{label: label}) when is_binary(label) and label != "", do: label
  defp extlink_label(%{site: site}) when is_binary(site) and site != "", do: site
  defp extlink_label(_), do: "Link"

  defp extlink_url(%{url: url}) when is_binary(url) and url != "", do: url
  defp extlink_url(_), do: nil
end
