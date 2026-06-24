defmodule KaguyaWeb.SharedComponents.UserAvatar do
  @moduledoc """
  Shared user avatar component — Phoenix-side port of
  `../personal/legacy-next-app/src/components/shared/UserAvatar.tsx` (+ `AvatarFallbackIcon.tsx`).

  One reusable HEEx component replacing six per-domain `avatar/1`
  definitions (`app_navbar`, `home/activity_components`, `comments`,
  `discussions`, `lists/cards`, `profile/shared`) plus the dozens of
  inline `<img class="… rounded-full object-cover">` callsites scattered
  across LiveView templates.

  See `docs/migrations/nextjs-liveview/plans/component-parity-plan.md` § 1.

  ## API

  The unifying call shape is the one every existing caller already used:

      <.user_avatar user={@user} size="size-10" />

  - `size` is a Tailwind size class (`size-8`, `size-[26px] lg:size-[36px]`).
    All six legacy avatar defs took the size this way.
  - Avatar URL is resolved from `:avatar_url` (preferred — matches
    `app_navbar.normalize_viewer/1`), falling back to
    `:avatar_urls.small` / `:avatar_urls.medium` per `variant`.
  - When the user has no avatar, `fallback` decides the rendered
    placeholder:

    - `:initials` (default) — single capitalized initial in a muted circle
      (matches `comments`, `home/activity`, `app_navbar`, `lists`)
    - `:default_url` — production default image
      (matches the previous `profile/shared` behavior)
    - `:empty` — a blank colored disc (matches `discussions`)

  - `link={true}` wraps the avatar in an `<a href="/@username">` (matches
    the `comments` `linked` clause and `lists/cards` `user_avatar`).
  - `srcset` is emitted automatically when both `:small` and `:medium`
    URLs are available, matching `UserAvatar.tsx`'s 120 w / 360 w pair.

  ## Examples

      <%!-- Comment author, linked, mobile/desktop responsive --%>
      <.user_avatar user={@comment.user} size="size-[26px] lg:size-[36px]" link />

      <%!-- Sidebar member card with explicit srcset --%>
      <.user_avatar user={@member} size="size-[100px]" sizes="(max-width: 768px) 90px, 100px" />

      <%!-- Production-style default fallback URL (used on profile sidebars) --%>
      <.user_avatar user={@user} size="size-10" fallback={:default_url} />
  """

  use KaguyaWeb, :html

  @default_fallback_url "https://images.kaguya.io/users/avatars/default-120w.webp"

  attr :user, :map,
    required: true,
    doc: "Map carrying `:avatar_url` or `:avatar_urls`, plus `:display_name` / `:username`."

  attr :size, :string,
    default: "size-10",
    doc: "Tailwind size class(es). Matches the legacy `size` attr every avatar def used."

  attr :class, :any, default: nil, doc: "Extra classes merged onto the avatar element."

  attr :variant, :atom,
    default: :default,
    values: [:default, :snapshot],
    doc: "`:default` uses `avatar_urls`, `:snapshot` uses the single `avatar_url` snapshot."

  attr :fallback, :atom,
    default: :initials,
    values: [:initials, :default_url, :empty, :silhouette],
    doc:
      "Rendered placeholder when the user has no avatar. `:silhouette` mirrors `../personal/legacy-next-app/src/components/shared/AvatarFallbackIcon.tsx` — scales with container, ideal for large avatars."

  attr :link, :boolean, default: false, doc: "Wrap in `<a href=\"/@username\">`."

  attr :loading, :string,
    default: "lazy",
    values: ["lazy", "eager"]

  attr :fetchpriority, :string, default: nil
  attr :sizes, :string, required: true, doc: "HTML `sizes` attr for `srcset` resolution."
  attr :alt, :string, default: nil
  attr :rest, :global

  def user_avatar(assigns) do
    assigns =
      assigns
      |> assign(:src, avatar_src(assigns.user, assigns.variant, assigns.fallback))
      |> assign(:srcset, avatar_srcset(assigns.user, assigns.variant))
      |> assign(:alt, assigns.alt || display_name(assigns.user))
      |> assign(:has_image?, has_image?(assigns.user, assigns.fallback))

    ~H"""
    <%= if @link and profile_href(@user) do %>
      <.link navigate={profile_href(@user)} class="shrink-0">
        <.avatar_inner
          src={@src}
          srcset={@srcset}
          sizes={@sizes}
          size={@size}
          class={@class}
          alt={@alt}
          loading={@loading}
          fetchpriority={@fetchpriority}
          fallback={@fallback}
          user={@user}
          has_image?={@has_image?}
          {@rest}
        />
      </.link>
    <% else %>
      <.avatar_inner
        src={@src}
        srcset={@srcset}
        sizes={@sizes}
        size={@size}
        class={@class}
        alt={@alt}
        loading={@loading}
        fetchpriority={@fetchpriority}
        fallback={@fallback}
        user={@user}
        has_image?={@has_image?}
        {@rest}
      />
    <% end %>
    """
  end

  attr :src, :string, default: nil
  attr :srcset, :string, default: nil
  attr :sizes, :string, default: nil
  attr :size, :string, required: true
  attr :class, :any, default: nil
  attr :alt, :string, required: true
  attr :loading, :string, required: true
  attr :fetchpriority, :string, default: nil
  attr :fallback, :atom, required: true
  attr :user, :map, required: true
  attr :has_image?, :boolean, required: true
  attr :rest, :global

  defp avatar_inner(assigns) do
    ~H"""
    <%= if @has_image? do %>
      <img
        src={@src}
        srcset={@srcset}
        sizes={@sizes}
        alt={@alt}
        loading={@loading}
        fetchpriority={@fetchpriority}
        decoding="async"
        class={[@size, "shrink-0 rounded-full bg-[rgb(var(--surface-elevated))] object-cover", @class]}
        {@rest}
      />
    <% else %>
      <.avatar_fallback
        fallback={@fallback}
        user={@user}
        size={@size}
        class={@class}
        alt={@alt}
        {@rest}
      />
    <% end %>
    """
  end

  attr :fallback, :atom, required: true
  attr :user, :map, required: true
  attr :size, :string, required: true
  attr :class, :any, default: nil
  attr :alt, :string, required: true
  attr :rest, :global

  defp avatar_fallback(%{fallback: :default_url} = assigns) do
    assigns = assign(assigns, :default_url, @default_fallback_url)

    ~H"""
    <img
      src={@default_url}
      alt={@alt}
      loading="lazy"
      decoding="async"
      class={[@size, "shrink-0 rounded-full bg-[rgb(var(--surface-elevated))] object-cover", @class]}
      {@rest}
    />
    """
  end

  defp avatar_fallback(%{fallback: :empty} = assigns) do
    ~H"""
    <span
      class={[@size, "block shrink-0 rounded-full bg-[rgb(var(--surface-elevated))]", @class]}
      aria-label={@alt}
      role="img"
      {@rest}
    />
    """
  end

  defp avatar_fallback(%{fallback: :silhouette} = assigns) do
    ~H"""
    <span
      class={[
        @size,
        "relative flex shrink-0 items-center justify-center overflow-hidden rounded-full bg-[#1d1d1d]",
        @class
      ]}
      aria-label={@alt}
      role="img"
      {@rest}
    >
      <Lucide.user_round
        class="absolute h-[87.5%] w-[81.25%] fill-[#C5C7C9] stroke-[#C5C7C9]"
        style="bottom: -12.5%"
        aria-hidden
      />
    </span>
    """
  end

  defp avatar_fallback(assigns) do
    assigns = assign(assigns, :initial, initial(assigns.user))

    ~H"""
    <span
      class={[
        @size,
        "flex shrink-0 items-center justify-center rounded-full",
        "bg-[rgb(var(--surface-banner))]/40 text-xs text-[rgb(var(--foreground-secondary))]",
        @class
      ]}
      aria-label={@alt}
      role="img"
      {@rest}
    >
      {@initial}
    </span>
    """
  end

  # ---------------------------------------------------------------------------
  # Helpers — URL resolution
  # ---------------------------------------------------------------------------

  defp has_image?(user, fallback) when fallback in [:default_url] do
    is_map(user) and avatar_url_for(user, :default) != nil
  end

  defp has_image?(user, _fallback), do: is_map(user) and avatar_url_for(user, :default) != nil

  defp avatar_src(user, variant, fallback) do
    case avatar_url_for(user, variant) do
      url when is_binary(url) and url != "" -> url
      _ when fallback == :default_url -> @default_fallback_url
      _ -> nil
    end
  end

  defp avatar_url_for(user, _variant) when not is_map(user), do: nil

  defp avatar_url_for(user, :snapshot) do
    case Map.get(user, :avatar_url) do
      url when is_binary(url) and url != "" -> url
      _ -> avatar_url_for(user, :default)
    end
  end

  defp avatar_url_for(user, :default) do
    cond do
      is_binary(Map.get(user, :avatar_url)) and Map.get(user, :avatar_url) != "" ->
        Map.get(user, :avatar_url)

      is_map(Map.get(user, :avatar_urls)) ->
        urls = Map.get(user, :avatar_urls)

        Map.get(urls, :small) || Map.get(urls, "small") ||
          Map.get(urls, :medium) || Map.get(urls, "medium")

      true ->
        nil
    end
  end

  defp avatar_srcset(user, _variant) when not is_map(user), do: nil

  defp avatar_srcset(user, _variant) do
    case Map.get(user, :avatar_urls) do
      %{} = urls ->
        small = Map.get(urls, :small) || Map.get(urls, "small")
        medium = Map.get(urls, :medium) || Map.get(urls, "medium")

        [
          {small, "120w"},
          {medium, "360w"}
        ]
        |> Enum.reject(fn {url, _w} -> is_nil(url) or url == "" end)
        |> case do
          [] -> nil
          [_only] -> nil
          entries -> Enum.map_join(entries, ", ", fn {url, w} -> "#{url} #{w}" end)
        end

      _ ->
        nil
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers — display name / initials / link
  # ---------------------------------------------------------------------------

  defp display_name(user) when not is_map(user), do: "User"

  defp display_name(user) do
    case Map.get(user, :display_name) do
      name when is_binary(name) and name != "" ->
        name

      _ ->
        case Map.get(user, :username) do
          name when is_binary(name) and name != "" -> name
          _ -> "User"
        end
    end
  end

  defp initial(user) when not is_map(user), do: "?"

  defp initial(user) do
    # Pull the first grapheme directly instead of pattern-matching on the
    # "User" sentinel — a real user literally named "User" should get "U",
    # and an empty/whitespace name should fall through to "?". We also
    # check `username` as a final fallback in case `display_name` was set
    # to whitespace.
    [user[:display_name], user[:username]]
    |> Enum.map(&first_grapheme/1)
    |> Enum.find("?", &(&1 != nil))
  end

  defp first_grapheme(nil), do: nil

  defp first_grapheme(name) when is_binary(name) do
    case name |> String.trim() |> String.graphemes() do
      [] -> nil
      [first | _] -> String.upcase(first)
    end
  end

  defp first_grapheme(_), do: nil

  defp profile_href(user) when is_map(user) do
    case Map.get(user, :username) do
      username when is_binary(username) and username != "" -> "/@#{username}"
      _ -> nil
    end
  end

  defp profile_href(_), do: nil
end
