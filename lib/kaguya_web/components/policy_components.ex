defmodule KaguyaWeb.PolicyComponents do
  @moduledoc """
  Shared layout primitives for the static policy / about / FAQ pages.
  """

  use KaguyaWeb, :html

  @policy_groups [
    %{
      label: "About",
      pages: [
        %{href: "/about", label: "About"},
        %{href: "/development", label: "Development"},
        %{href: "/faq", label: "FAQ"}
      ]
    },
    %{
      label: "Policies",
      pages: [
        %{href: "/community-guidelines", label: "Community guidelines"},
        %{href: "/review-guidelines", label: "Review guidelines"}
      ]
    },
    %{
      label: "Reference",
      pages: [
        %{href: "/content-policy", label: "Content policy"},
        %{href: "/formatting-help", label: "Formatting help"}
      ]
    },
    %{
      label: "Legal",
      pages: [
        %{href: "/privacy-policy", label: "Privacy policy"},
        %{href: "/terms", label: "Terms of use"}
      ]
    }
  ]

  attr :title, :string, required: true
  attr :current_path, :string, default: "/"
  slot :inner_block, required: true

  def policy_shell(assigns) do
    assigns = assign(assigns, :groups, @policy_groups)

    ~H"""
    <div class="mt-8 sm:mt-16">
      <div class="mx-auto mb-8 max-w-[75ch] px-5 sm:px-8 xl:hidden">
        <.policy_sidebar groups={@groups} current_path={@current_path} />
      </div>

      <div class="xl:mx-auto xl:flex xl:max-w-6xl xl:items-start xl:gap-12 xl:px-8">
        <aside class="hidden xl:sticky xl:top-[calc(72px+4rem)] xl:block xl:shrink-0 xl:pb-32">
          <.policy_sidebar groups={@groups} current_path={@current_path} />
        </aside>

        <div class="xl:min-w-0 xl:flex-1">
          <div class="mx-auto mb-16 w-full max-w-[75ch] px-5 sm:mb-32 sm:px-8">
            <h1 class="text-foreground-primary mb-4 text-xl font-semibold sm:mb-8 sm:text-3xl md:text-4xl">
              {@title}
            </h1>
            {render_slot(@inner_block)}
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :groups, :list, required: true
  attr :current_path, :string, required: true

  defp policy_sidebar(assigns) do
    ~H"""
    <nav class="flex flex-col gap-6">
      <div :for={group <- @groups}>
        <span class="text-foreground-quaternary mb-2 block text-xs font-medium tracking-wider uppercase">
          {group.label}
        </span>
        <div class="flex flex-col">
          <.link
            :for={page <- group.pages}
            navigate={page.href}
            class={[
              "border-l py-1 pl-4 text-left text-base whitespace-nowrap transition-colors",
              if(@current_path == page.href,
                do: "border-foreground-primary text-foreground-primary",
                else:
                  "border-foreground-tertiary hover:text-foreground-secondary text-foreground-tertiary"
              )
            ]}
          >
            {page.label}
          </.link>
        </div>
      </div>
    </nav>
    """
  end
end
