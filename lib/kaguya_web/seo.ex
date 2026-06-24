defmodule KaguyaWeb.SEO do
  @moduledoc """
  Builders that produce SEO assigns for LiveView pages, mirroring the Next.js
  frontend's `generateMetadata` output for strict parity.

  Each builder returns a map of socket assigns ready to splat into
  `assign/2`:

      socket |> assign(KaguyaWeb.SEO.vn(vn))

  The root layout (`lib/kaguya_web/components/layouts/root.html.heex`) reads
  these assigns: `page_title`, `meta_description`, `meta_robots`,
  `canonical_url`, `og_title`, `og_description`, `og_url`, `og_type`,
  `og_image`, `og_image_width`, `og_image_height`, `og_image_alt`,
  `twitter_card`, `twitter_title`, `twitter_description`, `twitter_image`,
  and `json_ld`.
  """

  alias KaguyaWeb.SEO.JsonLd

  @base_url "https://kaguya.io"
  @site_name "Kaguya"

  def base_url, do: @base_url
  def site_name, do: @site_name

  # ============================================================
  # VN
  # ============================================================

  @doc """
  Builds SEO assigns for a VN detail page. Mirrors
  ../personal/legacy-next-app/src/app/(main)/(maxWidthWrapper)/vn/[slug]/(root)/page.tsx
  """
  def vn(vn) do
    producer_name =
      case nonempty(producer_names(vn)) do
        nil -> "Unknown Developer"
        n -> n
      end

    meta_title = "#{vn.title} by #{producer_name}"

    stripped = strip_tags(Map.get(vn, :description))

    description =
      case stripped do
        "" -> fallback_vn_description(vn, producer_name)
        s -> s
      end
      |> truncate(300)

    featured = get_in(vn, [:featured_screenshot, :large])
    has_screenshot? = is_binary(featured) and featured != ""

    cover_image =
      get_in(vn, [:images, :large]) ||
        get_in(vn, [:images, :xl]) ||
        get_in(vn, [:images, :medium]) ||
        get_in(vn, [:images, :small]) || ""

    og_image = nonempty(if has_screenshot?, do: featured, else: cover_image)
    canonical = @base_url <> "/vn/#{vn.slug}"

    %{
      page_title: meta_title,
      meta_description: description,
      meta_robots: nil,
      canonical_url: canonical,
      og_title: meta_title,
      og_description: description,
      og_url: canonical,
      og_type: "website",
      og_image: og_image,
      og_image_width: if(has_screenshot? and og_image, do: 1200, else: nil),
      og_image_height: if(has_screenshot? and og_image, do: 630, else: nil),
      og_image_alt: nil,
      twitter_card: if(has_screenshot?, do: "summary_large_image", else: "summary"),
      twitter_title: meta_title,
      twitter_description: description,
      twitter_image: og_image,
      json_ld: JsonLd.video_game(vn) |> encode()
    }
  end

  def vn_not_found do
    # The legacy Next.js VN generateMetadata omitted `robots` on not-found,
    # leaving 404s indexable. That was always questionable; we now noindex VN
    # not-found like every other not-found state rather than preserve the quirk.
    not_found_assigns(
      "Visual Novel Not Found",
      "The visual novel you are looking for does not exist."
    )
  end

  # ============================================================
  # Developer / Producer
  # ============================================================

  @doc """
  Builds SEO assigns for a producer detail page. Mirrors
  ../personal/legacy-next-app/src/app/(main)/(maxWidthWrapper)/developer/[slug]/page.tsx
  """
  def developer(producer, opts \\ []) do
    total_count = Keyword.get(opts, :total_count, 0)
    first_vn_title = Keyword.get(opts, :first_vn_title)

    name = nonempty(Map.get(producer, :name)) || "Producer"
    producer_type = Map.get(producer, :producer_type)

    raw_description =
      case nonempty(Map.get(producer, :description)) do
        nil -> developer_fallback_description(name, producer_type, total_count, first_vn_title)
        desc -> desc
      end

    description =
      raw_description
      |> strip_tags()
      |> String.slice(0, 155)

    title = "#{name} (Visual Novel Producer)"
    canonical = @base_url <> "/developer/#{producer.slug}"

    %{
      page_title: title,
      meta_description: description,
      meta_robots: nil,
      canonical_url: canonical,
      og_title: title,
      og_description: description,
      og_url: canonical,
      og_type: "profile",
      og_image: nil,
      og_image_width: nil,
      og_image_height: nil,
      og_image_alt: nil,
      twitter_card: "summary",
      twitter_title: title,
      twitter_description: description,
      twitter_image: nil,
      json_ld: JsonLd.organization(producer) |> encode()
    }
  end

  def developer_not_found do
    not_found_assigns(
      "Producer Not Found • Kaguya",
      "The producer you are looking for does not exist."
    )
  end

  # ============================================================
  # User list
  # ============================================================

  @doc """
  Builds SEO assigns for a user-list detail page. Mirrors
  ../personal/legacy-next-app/src/app/(main)/(maxWidthWrapper)/users/[username]/list/[slug]/page.tsx
  """
  def list(list, owner, items, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 100)
    total_count = Keyword.get(opts, :total_count, length(items))

    list_name = nonempty(Map.get(list, :name)) || humanize_slug(Map.get(list, :slug))

    owner_name =
      case nonempty(owner_display_name(owner)) do
        nil -> "a Kaguya reader"
        n -> n
      end

    page_title = "#{list_name}, a list of visual novels by #{owner_name} • Kaguya"

    vn_titles =
      items
      |> Enum.take(5)
      |> Enum.map(&get_in(&1, [:visual_novel, :title]))
      |> Enum.filter(&is_binary/1)

    user_desc =
      list
      |> Map.get(:description)
      |> strip_tags()

    og_description =
      cond do
        user_desc != "" ->
          if String.length(user_desc) > 300 do
            String.slice(user_desc, 0, 300) <> "…"
          else
            user_desc
          end

        vn_titles != [] ->
          tail = if total_count > length(vn_titles), do: " and more.", else: "."
          "A list of #{total_count} visual novels: #{Enum.join(vn_titles, ", ")}#{tail}"

        true ->
          "A list of #{total_count} visual novels by #{owner_name} on Kaguya."
      end

    meta_description = build_list_meta_description(total_count, vn_titles, user_desc)
    cover_url = first_list_image_url(items)
    canonical = @base_url <> "/@#{owner.username}/list/#{list.slug}"

    %{
      page_title: page_title,
      meta_description: meta_description,
      meta_robots: nil,
      canonical_url: canonical,
      og_title: list_name,
      og_description: og_description,
      og_url: canonical,
      og_type: "website",
      og_image: cover_url,
      og_image_width: nil,
      og_image_height: nil,
      og_image_alt: nil,
      twitter_card: "summary",
      twitter_title: list_name,
      twitter_description: og_description,
      twitter_image: cover_url,
      json_ld:
        JsonLd.item_list(list, owner, items,
          page: page,
          page_size: page_size,
          total_count: total_count
        )
        |> encode()
    }
  end

  def list_not_found do
    not_found_assigns(
      "List Not Found • Kaguya",
      "The list you are looking for does not exist."
    )
  end

  # ============================================================
  # Generic helpers
  # ============================================================

  @doc """
  Robots assign for any page we want kept out of the index: derivative or thin
  surfaces (profile tabs, history/diffs, similar/ratings lists), private/auth
  pages, edit/contribute forms, and not-found states.

  Always `follow`, never `nofollow`. Google discourages `nofollow` for crawling
  your own site; we want crawlers to keep traversing the internal links on these
  pages through to the canonical content they point at. The only lever here is
  index vs. noindex — link-following stays on.
  """
  def noindex, do: %{meta_robots: "noindex,follow"}

  @doc """
  Robots assign for a page we explicitly want indexed. Indexable pages don't
  strictly need a robots meta (absence == `index,follow`), but a few surfaces
  (browse, members, changes) set it explicitly to be unambiguous.
  """
  def index, do: %{meta_robots: "index,follow"}

  defp not_found_assigns(title, description) do
    %{
      page_title: title,
      meta_description: description,
      meta_robots: "noindex,follow",
      canonical_url: nil,
      og_title: title,
      og_description: description,
      og_url: nil,
      og_type: "website",
      og_image: nil,
      og_image_width: nil,
      og_image_height: nil,
      og_image_alt: nil,
      twitter_card: "summary",
      twitter_title: title,
      twitter_description: description,
      twitter_image: nil,
      json_ld: nil
    }
  end

  @doc """
  Encode a schema.org map for safe inclusion in a `<script>` tag.

  Matches the Next.js frontend's `JSON.stringify` output (no `/` escaping) so
  raw HTML diffs stay clean, while still escaping `</` → `<\\/` so a user-
  supplied string containing `</script>` can't terminate the surrounding
  script element.
  """
  def encode(nil), do: nil

  def encode(map) when is_map(map) do
    map
    |> Jason.encode!()
    |> String.replace("</", "<\\/")
  end

  def owner_display_name(%{display_name: name, username: username}) do
    if is_binary(name) and String.trim(name) != "", do: name, else: username
  end

  def owner_display_name(%{username: username}) when is_binary(username), do: username
  def owner_display_name(_), do: nil

  # ============================================================
  # Internals
  # ============================================================

  defp producer_names(vn) do
    (Map.get(vn, :producers) || [])
    |> Enum.map(&get_in(&1, [:producer, :name]))
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.join(", ")
  end

  defp fallback_vn_description(vn, producer_name) do
    intro =
      case release_year(Map.get(vn, :release_date)) do
        nil -> "#{vn.title} is a visual novel by #{producer_name}."
        year -> "#{vn.title} is a visual novel by #{producer_name} (#{year})."
      end

    length_part =
      case Map.get(vn, :length_minutes) do
        n when is_integer(n) and n > 0 -> "#{format_length(n)} length."
        _ -> nil
      end

    rating_part =
      with avg when is_number(avg) <- Map.get(vn, :average_rating),
           count when is_integer(count) and count >= 5 <- Map.get(vn, :ratings_count) do
        "Rated #{:erlang.float_to_binary(avg * 1.0, decimals: 1)}/10."
      else
        _ -> nil
      end

    safe_tags =
      (Map.get(vn, :tags) || [])
      |> Enum.filter(&spoiler_free?/1)
      |> Enum.take(4)
      |> Enum.map(&tag_display_name/1)
      |> Enum.filter(&is_binary/1)

    tags_part = if safe_tags != [], do: Enum.join(safe_tags, ", ") <> ".", else: nil

    [intro, length_part, rating_part, tags_part]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp spoiler_free?(tag) do
    case Map.get(tag, :spoiler_level) do
      nil -> true
      level when level in [0, "0", "NONE", "None", "none", :none] -> true
      _ -> false
    end
  end

  defp tag_display_name(tag) do
    Map.get(tag, :name) || get_in(tag, [:tag, :name])
  end

  defp developer_fallback_description(name, producer_type, total_count, first_vn_title) do
    article = if producer_type == "individual", do: "an", else: "a"

    type_label =
      cond do
        producer_type == "amateur" -> "indie"
        is_binary(producer_type) and producer_type != "" -> producer_type
        true -> "visual novel"
      end

    suffix =
      case nonempty(first_vn_title) do
        nil -> "."
        title -> ", including #{title}."
      end

    "#{name} is #{article} #{type_label} producer with #{total_count} visual novels listed on Kaguya#{suffix}"
  end

  defp build_list_meta_description(total_count, vn_titles, user_desc) do
    parts = []

    parts =
      if total_count > 0,
        do: parts ++ ["A list of #{total_count} visual novels compiled on Kaguya"],
        else: parts

    parts =
      if vn_titles != [],
        do: parts ++ [", including #{Enum.join(vn_titles, ", ")}"],
        else: parts

    parts = parts ++ ["."]

    parts =
      if user_desc != "" and is_binary(user_desc),
        do: parts ++ [" About this list: " <> user_desc],
        else: parts

    parts
    |> Enum.join("")
    |> String.slice(0, 300)
  end

  defp format_length(min) when is_integer(min) and min < 120, do: "Very short"
  defp format_length(min) when is_integer(min) and min < 600, do: "Short"
  defp format_length(min) when is_integer(min) and min < 1800, do: "Medium"
  defp format_length(min) when is_integer(min) and min < 3000, do: "Long"
  defp format_length(_), do: "Very long"

  defp release_year(<<year::binary-size(4), _::binary>>) do
    case Integer.parse(year) do
      {y, ""} -> y
      _ -> nil
    end
  end

  defp release_year(_), do: nil

  defp first_list_image_url([]), do: nil

  defp first_list_image_url([item | _]) do
    images = get_in(item, [:visual_novel, :images]) || %{}
    Map.get(images, :medium) || Map.get(images, :small)
  end

  defp first_list_image_url(_), do: nil

  defp humanize_slug(slug) when is_binary(slug) do
    slug
    |> String.split("-")
    |> Enum.map_join(" ", fn
      "" ->
        ""

      part ->
        first = String.first(part) || ""
        rest = String.slice(part, 1..-1//1) || ""
        String.upcase(first) <> rest
    end)
  end

  defp humanize_slug(_), do: ""

  defp strip_tags(nil), do: ""

  defp strip_tags(s) when is_binary(s) do
    s
    |> String.replace(~r/<[^>]*>/, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp strip_tags(_), do: ""

  defp truncate(s, max) when is_binary(s) do
    if String.length(s) <= max do
      s
    else
      s
      |> String.slice(0, max - 1)
      |> String.trim_trailing()
      |> Kernel.<>("…")
    end
  end

  defp truncate(_, _), do: ""

  defp nonempty(s) when is_binary(s) do
    case String.trim(s) do
      "" -> nil
      v -> v
    end
  end

  defp nonempty(_), do: nil
end
