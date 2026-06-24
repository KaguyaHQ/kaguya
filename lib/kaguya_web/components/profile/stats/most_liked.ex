defmodule KaguyaWeb.Components.Profile.Stats.MostLiked do
  @moduledoc """
  Most-liked review and list components for the profile stats dashboard.
  """

  use KaguyaWeb, :html

  import KaguyaWeb.Components.Profile.Stats.Charting
  import KaguyaWeb.Components.Profile.Stats.Primitives

  alias KaguyaWeb.Components.Shared.DisplayRatings
  alias KaguyaWeb.Components.VN.Cards
  alias KaguyaWeb.Format

  attr :username, :string, required: true
  attr :review, :map, default: nil
  attr :list, :map, default: nil

  def most_liked_section(assigns) do
    assigns = assign(assigns, :has_both, not is_nil(assigns.review) and not is_nil(assigns.list))

    ~H"""
    <div
      :if={@review || @list}
      class={[
        "grid min-h-[327px] gap-8 lg:gap-12",
        @has_both && "grid-cols-1 lg:grid-cols-2",
        !@has_both && "grid-cols-1"
      ]}
    >
      <.most_liked_review :if={@review} username={@username} review={@review} />
      <.most_liked_list
        :if={@list}
        username={@username}
        list={@list}
        has_review={not is_nil(@review)}
      />
    </div>
    """
  end

  attr :username, :string, required: true
  attr :review, :map, required: true

  defp most_liked_review(assigns) do
    vn = assigns.review.visual_novel

    assigns =
      assigns
      |> assign(:vn, vn)
      |> assign(
        :review_href,
        if(vn,
          do: "/@#{assigns.username}/reviews/#{vn.slug}",
          else: "/@#{assigns.username}/reviews"
        )
      )

    ~H"""
    <div class="px-0 pt-4 pb-0 shadow-none max-sm:rounded-none max-sm:border-t max-sm:border-[rgb(var(--border-divider))] lg:py-0">
      <.section_heading title="Most Liked Review" />

      <div class="relative mt-5 flex gap-[15px] max-lg:items-center lg:mt-6 lg:gap-5">
        <.link
          navigate={@review_href}
          class="absolute inset-0 z-1 rounded-lg"
          aria-label={"Read full review of #{@vn && @vn.title || "visual novel"}"}
        >
          <span class="sr-only">Read full review</span>
        </.link>

        <div
          :if={@vn}
          class="relative z-10 h-[156px] w-[104px] shrink-0 overflow-hidden rounded-[2px] shadow-[0px_4px_10px_0px_rgba(0,0,0,0.35)]"
        >
          <Cards.cover
            vn={@vn}
            sizes="104px"
            class="size-full rounded-[2px] border-none object-cover"
            fallback_class="rounded-[2px]"
          />
        </div>

        <div class="min-w-0 flex-1">
          <.link
            :if={@vn}
            navigate={"/vn/#{@vn.slug}"}
            class="font-source-serif relative z-10 mt-2 text-xl leading-[22px] font-semibold text-[rgb(var(--foreground-primary))] hover:text-[rgb(var(--text-link-hover))] lg:text-lg lg:leading-[125%]"
          >
            {@vn.title}
          </.link>

          <div
            :if={is_number(@review.rating)}
            class="relative z-10 mt-3 flex w-fit items-center gap-1 lg:mt-2.5"
          >
            <DisplayRatings.display_ratings
              rating={@review.rating}
              icon_class="max-lg:size-4 text-[rgb(var(--icons-star-muted))]"
              half_rating_class="max-lg:text-sm max-lg:leading-5 text-[rgb(var(--icons-star-muted))]"
            />
            <span class="text-[9px] text-[#AAAAB8]">•</span>
            <.like_count count={@review.likes_count} />
          </div>

          <p
            :if={@review.content}
            class="mt-2.5 line-clamp-6 text-sm leading-[22px] wrap-break-word text-[rgb(var(--foreground-primary))] lg:line-clamp-8"
          >
            {@review.content}
          </p>

          <.link
            navigate={"/@#{@username}/reviews"}
            class="relative z-10 mt-6 hidden h-[38px] w-fit items-center justify-center rounded-[30px] border border-[rgb(var(--foreground-quaternary))]/10 px-[26px] py-2 text-sm leading-[22px] font-light text-[rgb(var(--foreground-primary))] hover:bg-white/2 lg:flex"
          >
            More reviews
          </.link>
        </div>
      </div>
    </div>
    """
  end

  attr :username, :string, required: true
  attr :list, :map, required: true
  attr :has_review, :boolean, required: true

  defp most_liked_list(assigns) do
    assigns =
      assigns
      |> assign(:list_href, "/@#{assigns.username}/list/#{assigns.list.slug}")
      |> assign(:covers, Enum.take(assigns.list.covers || [], 3))

    ~H"""
    <div class="px-0 pt-4 pb-0 shadow-none max-sm:rounded-none max-sm:border-t max-sm:border-[rgb(var(--border-divider))] lg:py-0">
      <.section_heading title="Most Liked List" />

      <div class="mt-5 lg:mt-6 lg:flex lg:items-start lg:gap-5">
        <.link
          navigate={@list_href}
          class={["flex shrink-0 items-center justify-center", @has_review && "lg:w-[139px]"]}
        >
          <div class="flex items-center justify-center -space-x-10 lg:-space-x-16">
            <Cards.cover
              :for={{vn, index} <- Enum.with_index(@covers)}
              vn={vn}
              sizes="96px"
              class={list_cover_class(index)}
              fallback_class="rounded-[2px]"
            />
          </div>
        </.link>

        <div class="mt-4 flex h-full flex-col lg:mt-0">
          <div class="grow space-y-1.5 lg:space-y-2.5">
            <.link
              navigate={@list_href}
              class="text-xl leading-[19px] font-semibold text-[rgb(var(--foreground-primary))] hover:text-[rgb(var(--text-link-hover))] lg:text-lg lg:leading-[125%]"
            >
              {@list.name}
            </.link>
            <div class="flex items-center gap-1">
              <span class="text-[13px] text-[#AAAAB8] lg:text-base">
                {@list.vns_count} {pluralize(@list.vns_count, "VN", "VNs")}
              </span>
              <span class="text-[9px] text-[#AAAAB8]">•</span>
              <.like_count count={@list.likes_count} />
            </div>
            <p
              :if={@list.description}
              class="pt-1 text-sm leading-[22px] wrap-break-word text-[rgb(var(--foreground-primary))]"
            >
              {@list.description}
            </p>
          </div>

          <.link
            navigate={"/@#{@username}/lists"}
            class="mt-6 hidden h-[38px] w-fit items-center justify-center rounded-[30px] border border-[rgb(var(--foreground-quaternary))]/10 px-[26px] py-2 text-sm leading-[22px] font-light text-[rgb(var(--foreground-primary))] hover:bg-white/2 lg:flex"
          >
            More lists
          </.link>
        </div>
      </div>
    </div>
    """
  end

  attr :count, :integer, required: true

  defp like_count(assigns) do
    ~H"""
    <span class="flex items-center gap-[3px]">
      <span class="text-[#AAAAB8]" aria-hidden="true">♡</span>
      <span class="text-[13px] font-light text-[#AAAAB8] lg:text-sm">
        {Format.integer(@count)} {pluralize(@count, "Like", "Likes")}
      </span>
    </span>
    """
  end

  defp list_cover_class(0),
    do:
      "h-[144px] w-[96px] rounded-[2px] border border-white/[12%] object-cover z-30 -rotate-[5deg]"

  defp list_cover_class(1),
    do: "h-[144px] w-[96px] rounded-[2px] border border-white/[12%] object-cover z-20"

  defp list_cover_class(2),
    do:
      "h-[144px] w-[96px] rounded-[2px] border border-white/[12%] object-cover z-10 rotate-[3deg] shadow-2xl"

  defp list_cover_class(_),
    do: "h-[144px] w-[96px] rounded-[2px] border border-white/[12%] object-cover"
end
