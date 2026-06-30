defmodule KaguyaWeb.CharacterLive.Show do
  use KaguyaWeb, :live_view

  alias Kaguya.Authorization
  alias Kaguya.Characters
  alias Kaguya.VisualNovels
  alias KaguyaWeb.VNLive.PageData
  alias KaguyaWeb.Components.Shared.NotFoundPage

  @min_ratings_to_display 10

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       slug: nil,
       page_title: "Character",
       character: nil,
       visual_novels: [],
       quotes: [],
       not_found?: false
     )}
  end

  @impl true
  def handle_params(%{"slug" => slug}, _uri, socket) do
    case Characters.get_character_page_by_slug(slug, socket.assigns.current_user) do
      {:ok, page} ->
        {:noreply,
         assign(socket,
           slug: slug,
           page_title: "#{page.character.name} (Character)",
           character: page.character,
           visual_novels: page.visual_novels,
           quotes: page.quotes,
           not_found?: false
         )}

      {:error, :not_found} ->
        {:noreply,
         assign(socket,
           slug: slug,
           page_title: "Character not found · Kaguya",
           not_found?: true
         )}
    end
  end

  @impl true
  def handle_event("toggle_favorite", _params, socket) do
    case socket.assigns.current_user do
      %{id: user_id} -> toggle_favorite(socket, user_id)
      _ -> {:noreply, put_flash(socket, :error, "Sign in to favorite characters")}
    end
  end

  def handle_event("toggle_quote_like", %{"quote-id" => quote_id}, socket) do
    case socket.assigns.current_user do
      %{id: _} = user ->
        {quotes, liked?} =
          Enum.map_reduce(socket.assigns.quotes, nil, fn quote, liked_acc ->
            if to_string(quote.id) == to_string(quote_id) do
              liked? = quote.liked_by_me || false

              updated = %{
                quote
                | liked_by_me: !liked?,
                  likes_count: max(0, (quote.likes_count || 0) + if(liked?, do: -1, else: 1))
              }

              {updated, liked?}
            else
              {quote, liked_acc}
            end
          end)

        socket = assign(socket, quotes: quotes)

        case PageData.toggle_quote_like(quote_id, liked?, user) do
          {:ok, _} -> {:noreply, socket}
          {:error, reason} -> {:noreply, put_flash(socket, :error, format_error(reason))}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Sign in to like quotes")}
    end
  end

  @impl true
  def render(%{not_found?: true} = assigns) do
    ~H"""
    <NotFoundPage.not_found_page variant={:overlay} />
    """
  end

  def render(assigns) do
    ~H"""
    <div class="pt-8 pb-[110px] sm:pb-32 md:pt-10 md:pb-20">
      <div class="relative mx-auto flex max-w-[640px] flex-col px-4 md:px-8 lg:max-w-[760px] lg:px-0">
        <div
          :if={can_moderate_db?(@current_user) && @character.hidden_at}
          class="mb-4 rounded-lg border border-red-500/20 bg-red-500/10 px-4 py-2.5 text-sm text-red-400"
        >
          This entry is hidden from public view.
        </div>

        <div class="flex flex-col items-center lg:flex-row lg:items-start lg:gap-8">
          <div
            :if={has_character_image?(@character)}
            class="group/hero relative max-w-[180px] lg:w-[200px] lg:max-w-none lg:shrink-0"
          >
            <KaguyaWeb.SharedComponents.CharacterImage.character_image
              character={@character}
              sizes="(max-width: 1024px) 180px, 200px"
              enable_nsfw_reveal
              class="aspect-2/3 w-full bg-[rgb(var(--surface-elevated))] object-cover shadow-[0_4px_12px_rgba(0,0,0,0.35)]"
              rounded="rounded-[4px]"
              loading="eager"
            />
          </div>

          <div class="mt-4 flex flex-col items-center gap-2 lg:mt-0 lg:min-w-0 lg:flex-1 lg:items-start">
            <div class="flex w-full items-start justify-between">
              <div class="flex flex-col items-center gap-1 lg:items-start">
                <h1 class="text-center text-[22px] leading-[27px] font-normal text-[rgb(var(--foreground-primary))] sm:text-[30px]/10 md:text-xl md:font-semibold lg:text-left lg:text-[28px] lg:leading-[34px]">
                  {@character.name}
                </h1>

                <div class="flex items-center gap-2">
                  <button
                    type="button"
                    phx-click="toggle_favorite"
                    aria-pressed={if @character.favorited_by_me, do: "true", else: "false"}
                    aria-label={
                      if @character.favorited_by_me,
                        do: "Remove from favorites",
                        else: "Add to favorites"
                    }
                    class={[
                      "group/fav flex shrink-0 items-center text-[rgb(var(--foreground-secondary))] transition-colors hover:text-[rgb(var(--like-heart))]",
                      @character.favorited_by_me && "text-[rgb(var(--like-heart))]"
                    ]}
                  >
                    <Lucide.heart
                      class={[
                        "size-[18px] transition-colors duration-100 group-hover/fav:fill-[rgb(var(--like-heart))]",
                        @character.favorited_by_me && "fill-[rgb(var(--like-heart))]"
                      ]}
                      aria-hidden
                    />
                  </button>

                  <.link
                    :if={(@character.favorites_count || 0) > 0}
                    navigate={"/character/#{@character.slug}/fans"}
                    class="text-[13px] text-[rgb(var(--foreground-secondary))] tabular-nums transition-colors hover:text-[rgb(var(--foreground-primary))] lg:text-sm"
                  >
                    {format_count(@character.favorites_count)}
                    {if @character.favorites_count == 1, do: "Fan", else: "Fans"}
                  </.link>
                </div>
              </div>

              <div class="hidden shrink-0 items-center gap-1.5 lg:flex">
                <span
                  :if={@character.is_locked}
                  class="flex h-[25px] items-center justify-center gap-1 rounded-[4px] border border-amber-500/20 bg-amber-500/15 px-[8px] py-[4px] text-[10px] leading-[16px] font-normal tracking-[0.06em] text-amber-400"
                >
                  Locked
                </span>
                <.link
                  :if={can_edit?(@current_user) && !@character.is_locked}
                  navigate={"/character/#{@character.slug}/edit"}
                  class="flex h-[25px] items-center justify-center gap-1 rounded-[4px] border border-[rgb(var(--chip-border-default))] px-[8px] py-[4px] text-[10px] leading-[16px] font-normal tracking-[0.06em] text-[rgb(var(--foreground-secondary))] transition-colors duration-200 hover:border-[rgb(var(--chip-border-hover))]"
                >
                  Edit
                </.link>
                <span
                  :if={can_edit?(@current_user) && @character.is_locked}
                  title="Entry is locked for editing"
                  class="flex h-[25px] cursor-not-allowed items-center justify-center gap-1 rounded-[4px] border border-[rgb(var(--chip-border-default))] px-[8px] py-[4px] text-[10px] leading-[16px] font-normal tracking-[0.06em] text-[rgb(var(--foreground-quaternary))] opacity-50"
                >
                  Edit
                </span>
                <.link
                  navigate={"/character/#{@character.slug}/history"}
                  class="flex h-[25px] items-center justify-center gap-1 rounded-[4px] border border-[rgb(var(--chip-border-default))] px-[8px] py-[4px] text-[10px] leading-[16px] font-normal tracking-[0.06em] text-[rgb(var(--foreground-secondary))] transition-colors duration-200 hover:border-[rgb(var(--chip-border-hover))]"
                >
                  History
                </.link>
              </div>
            </div>

            <div :if={@character.description} class="mt-4 hidden lg:block">
              <KaguyaWeb.SharedComponents.Markdown.markdown
                content={@character.description}
                variant="plain"
                class="text-sm leading-[22px] text-[rgb(var(--foreground-secondary))] [&_a]:text-[rgb(var(--text-link-default))] [&_a:hover]:text-[rgb(var(--text-link-hover))] [&_p]:my-0 [&_p]:leading-6 [&_p+p]:mt-[1em]"
                read_more
                read_more_id={"char-desc-desktop-#{@character.slug}"}
                read_more_lines={12}
                read_more_limit={450}
              />
            </div>
          </div>
        </div>

        <div :if={@character.description} class="mt-6 lg:hidden">
          <KaguyaWeb.SharedComponents.Markdown.markdown
            content={@character.description}
            variant="plain"
            class="text-sm leading-[22px] text-[rgb(var(--foreground-secondary))] [&_a]:text-[rgb(var(--text-link-default))] [&_a:hover]:text-[rgb(var(--text-link-hover))] [&_p]:my-0 [&_p]:leading-6 [&_p+p]:mt-[1em]"
            read_more
            read_more_id={"char-desc-mobile-#{@character.slug}"}
            read_more_lines={8}
            read_more_limit={200}
          />
        </div>

        <section :if={@quotes != []} class="mt-6 lg:mt-9">
          <h2 class="mb-3 text-xs font-medium tracking-wide text-[rgb(var(--foreground-tertiary))] uppercase">
            Quotes
          </h2>
          <div class="flex flex-col gap-2.5">
            <blockquote :for={quote <- @quotes} class="group/quote-row flex items-start gap-3">
              <div class="flex-1">
                <p class="font-serif text-[15px] leading-relaxed text-[rgb(var(--foreground-secondary))]">
                  “{quote.quote}”
                </p>
              </div>

              <button
                type="button"
                phx-click="toggle_quote_like"
                phx-value-quote-id={quote.id}
                aria-pressed={if quote.liked_by_me, do: "true", else: "false"}
                class={[
                  "group/like relative flex shrink-0 items-center gap-1 text-[rgb(var(--foreground-secondary))] transition-colors hover:text-[rgb(var(--like-heart))]",
                  quote.liked_by_me && "text-[rgb(var(--like-heart))]"
                ]}
              >
                <Lucide.heart
                  class={[
                    "size-4 transition-colors duration-100 group-hover/like:fill-[rgb(var(--like-heart))]",
                    quote.liked_by_me && "fill-current",
                    quote.liked_by_me && "fill-[rgb(var(--like-heart))]"
                  ]}
                  aria-hidden
                />
                <span :if={(quote.likes_count || 0) > 0} class="text-xs tabular-nums">
                  {format_count(quote.likes_count)}
                </span>
              </button>
            </blockquote>
          </div>
        </section>

        <section id="vns" class="mt-6 scroll-mt-24">
          <h2 class="mb-3 text-xs font-medium tracking-wide text-[rgb(var(--foreground-tertiary))] uppercase">
            Appears in
          </h2>

          <div
            :if={@visual_novels == []}
            class="flex items-center justify-center py-12 text-[rgb(var(--foreground-secondary))]"
          >
            No visual novels found for this character.
          </div>

          <div :if={@visual_novels != []} class="flex flex-wrap gap-3 sm:gap-4">
            <div
              :for={appearance <- @visual_novels}
              class="flex w-[calc(33.333%-8px)] flex-col sm:w-[140px] md:w-[130px]"
            >
              <.link navigate={"/vn/#{appearance.visual_novel.slug}"} class="block">
                <KaguyaWeb.SharedComponents.Cover.cover
                  vn={appearance.visual_novel}
                  sizes="(min-width: 768px) 130px, (min-width: 640px) 140px, 33vw"
                  class="aspect-2/3 w-full rounded-[4px]"
                  fallback_class="rounded-[4px]"
                />
              </.link>

              <div class="mt-1 flex items-center justify-between gap-2 text-[11px]">
                <span class="truncate text-[rgb(var(--foreground-secondary))]">
                  {format_role(appearance.role)}
                </span>
                <div
                  :if={show_rating?(appearance.visual_novel)}
                  class="flex shrink-0 items-center gap-1"
                >
                  <span class="text-[rgb(var(--foreground-secondary))]">
                    {format_rating(appearance.visual_novel.average_rating)}
                  </span>
                  <span class="text-[rgb(var(--foreground-tertiary))]">
                    ({format_count(appearance.visual_novel.ratings_count)})
                  </span>
                </div>
              </div>
            </div>
          </div>
        </section>
      </div>
    </div>
    """
  end

  defp toggle_favorite(socket, user_id) do
    character = socket.assigns.character
    favorited? = character.favorited_by_me || false
    delta = if favorited?, do: -1, else: 1

    optimistic = %{
      character
      | favorited_by_me: !favorited?,
        favorites_count: max(0, (character.favorites_count || 0) + delta)
    }

    persist =
      if favorited? do
        Kaguya.Users.remove_favorite_character(user_id, character.id)
      else
        Kaguya.Users.add_favorite_character(user_id, character.id)
      end

    case persist do
      {:ok, _} ->
        {:noreply, assign(socket, character: optimistic)}

      {:error, :limit_exceeded} ->
        {:noreply, put_flash(socket, :error, "You've reached your favorite characters limit")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, format_error(reason))}
    end
  end

  defp has_character_image?(character) do
    urls = VisualNovels.build_character_image_urls(character) || %{}

    is_binary(Map.get(urls, :large)) or is_binary(Map.get(urls, :small)) or
      is_binary(Map.get(urls, :medium))
  end

  defp can_edit?(%{can_edit: false}), do: false
  defp can_edit?(%{id: _}), do: true
  defp can_edit?(_), do: false

  defp can_moderate_db?(user), do: Authorization.can_moderate_db?(user)

  defp format_role(:main), do: "Main"
  defp format_role(:primary), do: "Primary"
  defp format_role(:side), do: "Side"
  defp format_role(:appears), do: "Appears"
  defp format_role(nil), do: ""
  defp format_role(role), do: role |> to_string() |> String.capitalize()

  defp show_rating?(%{average_rating: rating, ratings_count: count})
       when is_number(rating) and is_integer(count) do
    count >= @min_ratings_to_display
  end

  defp show_rating?(_), do: false

  defp format_rating(rating) when is_float(rating),
    do: :erlang.float_to_binary(rating, decimals: 1)

  defp format_rating(rating) when is_integer(rating), do: "#{rating}.0"
  defp format_rating(_), do: nil

  defp format_count(count) when is_integer(count) and count >= 1_000_000 do
    "#{Float.round(count / 1_000_000, 1)}M"
  end

  defp format_count(count) when is_integer(count) and count >= 1_000 do
    "#{Float.round(count / 1_000, 1)}K"
  end

  defp format_count(count) when is_integer(count), do: Integer.to_string(count)
  defp format_count(_), do: "0"

  defp format_error(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> inspect()
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end
