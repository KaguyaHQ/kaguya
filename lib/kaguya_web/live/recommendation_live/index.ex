defmodule KaguyaWeb.RecommendationLive.Index do
  use KaguyaWeb, :live_view

  alias Kaguya.{Screenshots, VNTags, VisualNovels}
  alias Kaguya.Recommendations.PregeneratedRecs
  alias KaguyaWeb.Components.Recommendations.List, as: RecommendationList

  @limit 25
  @vndb_uid_regex ~r/^u\d{1,10}$/
  @vndb_username_regex ~r/^[a-z0-9_-]{2,15}$/
  @landing_title "Recommendations • Kaguya"
  @landing_description "Paste a VNDB user ID to see Kaguya's personalized recommendations. No sign-up required."

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: @landing_title,
       meta_description: @landing_description,
       vndb_user_id: nil,
       query: "",
       rec_items: [],
       pref_count: nil,
       masked_count: nil,
       input_error: nil,
       not_found?: false,
       not_ready?: false,
       error_message: nil
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    raw_identifier = Map.get(params, "vndb_user_id")
    identifier = normalize_identifier(raw_identifier)

    case identifier do
      nil ->
        {:noreply, assign_landing(socket)}

      ident ->
        # Per-user result pages (/vn-recommender/:id) are generated, thin, and
        # unbounded by external VNDB id — noindex them. The bare /vn-recommender
        # landing (nil identifier) stays indexable.
        socket = assign(socket, KaguyaWeb.SEO.noindex())

        if valid_identifier?(ident) do
          if raw_identifier != ident and Regex.match?(@vndb_uid_regex, ident) do
            {:noreply, push_navigate(socket, to: ~p"/vn-recommender/#{ident}", replace: true)}
          else
            load_recommendations(socket, ident)
          end
        else
          {:noreply,
           assign(socket,
             page_title: @landing_title,
             meta_description: @landing_description,
             vndb_user_id: nil,
             query: ident,
             rec_items: [],
             pref_count: nil,
             masked_count: nil,
             input_error:
               "That doesn't look like a VNDB user id or username. Try u234181 or a username like beatrice.",
             not_found?: false,
             not_ready?: false,
             error_message: nil
           )}
        end
    end
  end

  @impl true
  def handle_event("search", %{"vndb_user_id" => raw_input}, socket) do
    case normalize_identifier(raw_input) do
      nil ->
        {:noreply, assign(socket, input_error: "Enter a VNDB user id or username.", query: "")}

      ident ->
        if valid_identifier?(ident) do
          if ident == socket.assigns.query do
            load_recommendations(socket, ident)
          else
            {:noreply, push_navigate(socket, to: ~p"/vn-recommender/#{ident}")}
          end
        else
          {:noreply,
           assign(socket,
             input_error:
               "That doesn't look like a VNDB user id or username. Try u234181 or a username like beatrice.",
             query: ident
           )}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="pb-24">
      <div class="mx-auto mt-10 mb-16 flex w-full max-w-[988px] flex-col px-4 sm:px-0 md:mt-16 lg:px-0">
        <header class="mx-auto flex w-full max-w-[720px] flex-col items-center gap-8 text-center md:gap-10">
          <h1 class="font-source-serif text-foreground-primary text-[40px] leading-none font-light tracking-[-0.02em] lg:text-[64px]">
            Recommendations
          </h1>
          <p class="sr-only">
            Enter a VNDB user id (u12345) to view public recommendations generated from their votes.
          </p>
          <form phx-submit="search" class="mx-auto flex w-full max-w-[520px] flex-col gap-2">
            <div class="relative">
              <input
                type="search"
                name="vndb_user_id"
                value={@query}
                placeholder="VNDB username or user id"
                autocomplete="off"
                autocapitalize="none"
                spellcheck="false"
                aria-required="true"
                aria-invalid={to_string(is_binary(@input_error))}
                aria-describedby={if is_binary(@input_error), do: "vndb-user-id-error"}
                data-bwignore="true"
                data-1p-ignore="true"
                data-lpignore="true"
                data-form-type="other"
                class="bg-surface-elevated border-text-field-border focus-visible:border-text-field-border-focus placeholder:text-foreground-quaternary text-foreground-primary h-12 w-full rounded-full border py-1 pr-14 pl-5 text-base shadow-none transition-colors focus-visible:outline-hidden dark:bg-transparent dark:shadow-xs [&::-webkit-search-cancel-button]:appearance-none"
              />
              <button
                type="submit"
                class="active:bg-button-background-brand-pressed bg-button-background-brand-default hover:bg-button-background-brand-hover text-button-text-on-brand absolute top-1/2 right-1.5 flex size-9 -translate-y-1/2 cursor-pointer items-center justify-center rounded-full transition-colors disabled:cursor-not-allowed disabled:opacity-40"
                aria-label="Get recommendations"
              >
                <Lucide.arrow_right class="size-4" aria-hidden />
              </button>
            </div>
            <p
              :if={is_binary(@input_error)}
              id="vndb-user-id-error"
              role="alert"
              class="text-center text-[13px] text-red-400"
            >
              {@input_error}
            </p>
          </form>
        </header>

        <div class="recs-reveal mt-12 md:mt-16">
          <.error_card :if={@not_found?} title="VNDB user not found">
            We couldn't find that VNDB user. Double-check the ID and try again.
          </.error_card>

          <.error_card :if={@not_ready?} title="Not enough data">
            We couldn't find enough of this user's rated or labeled VNs to make personalized recommendations.
          </.error_card>

          <.error_card :if={is_binary(@error_message)} title="Couldn't load recommendations">
            {@error_message}
          </.error_card>

          <RecommendationList.recommendation_list
            :if={!@not_found? && !@not_ready? && !is_binary(@error_message) && @vndb_user_id != nil}
            recs={@rec_items}
            mode={:guest_vndb}
            vndb_user_id={@vndb_user_id}
            is_own_profile={false}
            is_refreshing={false}
            signals_count={@pref_count || 0}
            signals_required={3}
            current_user={@current_user}
          />
        </div>
      </div>
    </div>
    """
  end

  defp assign_landing(socket) do
    assign(socket,
      page_title: @landing_title,
      meta_description: @landing_description,
      vndb_user_id: nil,
      query: "",
      rec_items: [],
      pref_count: nil,
      masked_count: nil,
      input_error: nil,
      not_found?: false,
      not_ready?: false,
      error_message: nil
    )
  end

  defp normalize_identifier(raw) when is_binary(raw) do
    trimmed = String.trim(raw)

    cond do
      trimmed == "" ->
        nil

      match = Regex.run(~r/(?:^|\/)(u\d+)(?:\/|$)/i, trimmed) ->
        match |> Enum.at(1) |> String.downcase()

      Regex.match?(~r/^\d+$/, trimmed) ->
        "u#{trimmed}"

      true ->
        String.downcase(trimmed)
    end
    |> case do
      "" -> nil
      cleaned -> cleaned
    end
  end

  defp normalize_identifier(_), do: nil

  defp valid_identifier?(identifier) when is_binary(identifier),
    do:
      Regex.match?(@vndb_uid_regex, identifier) or Regex.match?(@vndb_username_regex, identifier)

  defp valid_identifier?(_), do: false

  defp load_recommendations(socket, identifier) do
    case PregeneratedRecs.recommend(identifier, limit: @limit) do
      {:ok, %{items: items, pref_count: pref_count, masked_count: masked_count}} ->
        resolved = resolved_identifier(identifier)

        {:noreply,
         assign(socket,
           vndb_user_id: resolved,
           page_title: "Recommendations for #{resolved} • Kaguya",
           meta_description:
             "See what Kaguya's recommendation algorithm picks for VNDB user #{resolved}.",
           query: identifier,
           rec_items: hydrate_recommendation_items(items),
           pref_count: pref_count,
           masked_count: masked_count,
           input_error: nil,
           not_found?: false,
           not_ready?: false,
           error_message: nil
         )}

      {:error, :not_found} ->
        {:noreply, assign_error(socket, identifier, not_found?: true)}

      {:error, :not_pregenerated} ->
        {:noreply, assign_error(socket, identifier, not_ready?: true)}

      {:error, _reason} ->
        {:noreply,
         assign_error(socket, identifier,
           error_message: "Something went wrong on our end. Please try again."
         )}
    end
  end

  defp assign_error(socket, identifier, overrides) do
    assign(
      socket,
      Keyword.merge(
        [
          vndb_user_id: nil,
          page_title: "Recommendations for #{identifier} • Kaguya",
          meta_description:
            "See what Kaguya's recommendation algorithm picks for VNDB user #{identifier}.",
          query: identifier,
          rec_items: [],
          pref_count: nil,
          masked_count: nil,
          input_error: nil,
          not_found?: false,
          not_ready?: false,
          error_message: nil
        ],
        overrides
      )
    )
  end

  defp resolved_identifier(identifier) do
    case PregeneratedRecs.resolve_ident(identifier) do
      {:ok, uid} -> uid
      :error -> identifier
    end
  end

  defp hydrate_recommendation_items([]), do: []

  defp hydrate_recommendation_items(items) do
    vn_ids = items |> Enum.map(& &1.visual_novel.id) |> Enum.uniq()
    screenshots_by_vn = Screenshots.list_screenshots_for_vns(nil, vn_ids)
    tags_by_vn = VNTags.list_tags_for_vns(nil, vn_ids)

    Enum.map(items, fn rec ->
      %{
        rank: rec.rank,
        score: rec.score,
        ease_score: rec.ease_score,
        relevance_pct: rec.relevance_pct || 0,
        total_positive_contribution: rec.total_positive_contribution,
        user_signal: nil,
        user_reading_status: nil,
        dismissed?: false,
        visual_novel:
          normalize_vn(
            rec.visual_novel,
            Map.get(screenshots_by_vn, rec.visual_novel.id, []),
            Map.get(tags_by_vn, rec.visual_novel.id, [])
          ),
        because_you_liked: Enum.map(rec.because_you_liked, &normalize_reason/1)
      }
    end)
  end

  defp normalize_vn(vn, screenshots, tags) do
    %{
      id: vn.id,
      title: vn.title,
      slug: vn.slug,
      images: VisualNovels.build_image_urls(vn),
      has_ero: vn.has_ero,
      is_image_nsfw: vn.is_image_nsfw,
      is_image_suggestive: vn.is_image_suggestive,
      screenshots: Enum.map(screenshots, &normalize_screenshot/1),
      tags: Enum.map(tags, &normalize_tag/1)
    }
  end

  defp normalize_screenshot(screenshot) do
    %{
      id: screenshot.id,
      images: VisualNovels.build_screenshot_urls(screenshot.id),
      is_nsfw: Map.get(screenshot, :is_nsfw, false),
      is_brutal: Map.get(screenshot, :is_brutal, false)
    }
  end

  defp normalize_tag(%{tag: tag} = row) do
    %{
      spoiler_level: row[:spoiler_level] || row["spoiler_level"],
      tag: %{
        id: tag.id,
        name: tag.name,
        display_name: Kaguya.Tags.Tag.display_name(tag),
        slug: tag.slug,
        category: tag.category,
        kind: tag.kind
      }
    }
  end

  defp normalize_reason(reason) do
    %{
      user_rating: reason.user_rating,
      user_status: reason.user_status,
      contribution: reason.contribution,
      visual_novel: %{
        id: reason.visual_novel.id,
        title: reason.visual_novel.title,
        slug: reason.visual_novel.slug,
        images: VisualNovels.build_image_urls(reason.visual_novel),
        is_image_nsfw: Map.get(reason.visual_novel, :is_image_nsfw, false),
        is_image_suggestive: Map.get(reason.visual_novel, :is_image_suggestive, false)
      }
    }
  end

  attr :title, :string, required: true
  slot :inner_block, required: true

  defp error_card(assigns) do
    ~H"""
    <div class="bg-surface-secondary border-border-divider mx-auto max-w-[640px] rounded-xl border px-5 py-8 sm:px-8 sm:py-10">
      <div class="flex flex-col gap-2">
        <h2 class="text-foreground-primary text-style-body1Medium">{@title}</h2>
        <p class="text-foreground-secondary text-style-body2Regular">
          {render_slot(@inner_block)}
        </p>
      </div>
    </div>
    """
  end
end
