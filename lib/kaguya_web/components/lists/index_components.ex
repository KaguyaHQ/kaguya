defmodule KaguyaWeb.Lists.IndexComponents do
  @moduledoc """
  Components for the public lists index.

  Data shaping stays in `KaguyaWeb.ListLive.Data`; list presentation delegates
  to the shared `KaguyaWeb.Lists.Cards` primitives so `/lists`, profile pages,
  and VN surfaces stay visually aligned.
  """

  use KaguyaWeb, :html

  alias KaguyaWeb.Lists.Cards, as: ListCards

  import KaguyaWeb.AuthPromptComponents, only: [auth_link: 1, auth_prompt_modal: 1]

  attr :popular_lists, :list, required: true
  attr :hidden_gem_lists, :list, required: true
  attr :recently_liked_lists, :list, required: true
  attr :recent_lists, :list, required: true
  attr :is_logged_in, :boolean, default: false
  attr :current_path, :string, default: "/lists"

  def lists_index(assigns) do
    ~H"""
    <div class="mx-auto mt-8 max-w-[988px] px-5 pb-[110px] sm:mt-6 sm:pb-32 lg:mt-12 lg:px-0">
      <div class="mx-auto flex items-center justify-center">
        <.auth_link
          href={~p"/list/new"}
          is_logged_in={@is_logged_in}
          modal_id="lists-auth-prompt"
          rel="nofollow noindex"
          class="bg-button-background-brand-default hover:bg-button-background-brand-hover text-button-text-on-brand flex size-fit items-center gap-1.5 rounded-[4px] px-6 py-2 text-sm font-normal transition max-sm:h-9 max-sm:max-w-[200px] max-sm:py-1.5"
        >
          <Lucide.plus class="size-[18px]" aria-hidden />
          <span class="text-style-body2Medium">Start Your Own List</span>
        </.auth_link>
      </div>

      <.auth_prompt_modal
        :if={!@is_logged_in}
        id="lists-auth-prompt"
        message="Sign in to create a list"
        return_to={@current_path}
      />

      <.featured_section
        :if={@popular_lists != []}
        title="Popular Lists"
        href="/lists/popular"
        lists={Enum.take(@popular_lists, 3)}
        class="mt-10 sm:mt-4 lg:mt-8"
      />

      <.featured_section
        :if={@hidden_gem_lists != []}
        title="Staff Picks"
        lists={Enum.take(@hidden_gem_lists, 3)}
        class="mt-10 hidden sm:mt-8 sm:block"
      />

      <div class="mt-12 grid gap-y-10 sm:gap-x-[47px] sm:gap-y-0 sm:max-lg:mt-8 md:grid-cols-[1fr_24.32%] lg:gap-x-20">
        <section>
          <.section_heading
            :if={@recently_liked_lists != [] || @recent_lists != []}
            title="Recently Liked"
          />
          <div class="sm:divide-border-divider mt-4 max-sm:space-y-6 sm:mt-0 sm:divide-y">
            <div
              :for={{list, index} <- Enum.with_index(Enum.take(@recently_liked_lists, 10))}
              class={[visibility_class(index), "sm:pt-4 sm:pb-6"]}
            >
              <ListCards.list_row list={list} />
            </div>
          </div>
        </section>

        <section>
          <.section_heading
            :if={@recent_lists != [] || @recently_liked_lists != []}
            title="New Lists"
          />
          <div class="mt-4 space-y-6 sm:max-lg:mt-3 md:max-lg:space-y-[19px]">
            <ListCards.list_card
              :for={{list, index} <- Enum.with_index(Enum.take(@recent_lists, 8))}
              list={list}
              sizes="(max-width: 640px) 67px, 93px"
              max_covers={5}
              class={visibility_class(index)}
              container_class="flex w-full -space-x-[29px] overflow-hidden rounded-[2px] sm:-space-x-10"
              grid_class="w-[67px] rounded-[2px] sm:w-[93px]"
              image_class="rounded-[2px]"
              title_class="mt-1.5 text-sm leading-[17px] font-semibold text-foreground-secondary dark:text-[#f9f9f9] sm:text-style-body2Medium"
              details_class="mt-1 gap-[7px]"
              details_variant="text"
            />
          </div>
        </section>
      </div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :href, :string, default: nil
  attr :lists, :list, required: true
  attr :class, :any, default: nil

  defp featured_section(assigns) do
    ~H"""
    <section class={@class}>
      <.section_heading title={@title} href={@href} />
      <div class="mt-4 grid gap-6 sm:grid-cols-2 sm:gap-7 md:grid-cols-3 lg:gap-[37px]">
        <ListCards.list_card
          :for={list <- @lists}
          list={list}
          sizes="(max-width: 640px) 33vw, 148px"
          max_covers={5}
          container_class="flex w-full overflow-hidden rounded-[4px] -space-x-[45px] sm:w-fit sm:-space-x-[112px]"
          grid_class="rounded-[4px] sm:w-[148px]"
          image_class="rounded-[4px]"
          title_class="max-sm:mt-2 text-foreground-secondary sm:text-style-body1Medium"
        />
      </div>
    </section>
    """
  end

  attr :title, :string, required: true
  attr :href, :string, default: nil

  defp section_heading(assigns) do
    ~H"""
    <h4 class="border-border-divider sm:text-style-heading3Regular text-foreground-primary border-x-0 border-t-0 border-b pb-1.5 text-base leading-[19px] font-normal">
      <%= if @href do %>
        <.link navigate={@href} class="lg:hover:text-text-link-hover w-fit transition">
          {@title}
        </.link>
      <% else %>
        {@title}
      <% end %>
    </h4>
    """
  end

  defp visibility_class(index) when index >= 7, do: "max-lg:hidden"
  defp visibility_class(index) when index >= 5, do: "max-sm:hidden"
  defp visibility_class(_index), do: nil
end
