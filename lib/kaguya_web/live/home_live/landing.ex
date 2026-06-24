defmodule KaguyaWeb.HomeLive.Landing do
  use KaguyaWeb, :live_view

  @hero_image "https://images.kaguya.io/ui/backdrop_cha_more.webp"
  @page_title "Kaguya • The social site for VN readers"
  @description "Track, rate, and review visual novels. Follow friends, make lists, and discover what to read next."
  @og_image "https://images.kaguya.io/ui/og-image-main.webp"
  @og_image_alt "Kaguya homepage preview"

  @doc "Public accessor for the hero backdrop URL — used for the preload link in HomeLive.Show."
  def hero_image_url, do: @hero_image

  @covers [
    %{
      title: "Full Metal Daemon Muramasa",
      slug: "full-metal-daemon-muramasa",
      images: %{
        small:
          "https://images.kaguya.io/visual_novels/019cba58-a759-7a8d-a189-b235997a52bd-128w.webp",
        medium:
          "https://images.kaguya.io/visual_novels/019cba58-a759-7a8d-a189-b235997a52bd-256w.webp",
        large:
          "https://images.kaguya.io/visual_novels/019cba58-a759-7a8d-a189-b235997a52bd-512w.webp",
        xl:
          "https://images.kaguya.io/visual_novels/019cba58-a759-7a8d-a189-b235997a52bd-1024w.webp"
      }
    },
    %{
      title: "Sona-Nyl of the Violet Shadows ~What Beautiful Memories~",
      slug: "sona-nyl-of-the-violet-shadows-what-beautiful",
      images: %{
        small:
          "https://images.kaguya.io/visual_novels/019cba58-5d9c-7f16-9235-14409452aa28-128w.webp",
        medium:
          "https://images.kaguya.io/visual_novels/019cba58-5d9c-7f16-9235-14409452aa28-256w.webp",
        large:
          "https://images.kaguya.io/visual_novels/019cba58-5d9c-7f16-9235-14409452aa28-512w.webp",
        xl:
          "https://images.kaguya.io/visual_novels/019cba58-5d9c-7f16-9235-14409452aa28-1024w.webp"
      }
    },
    %{
      title: "Umineko When They Cry - Question Arcs",
      slug: "umineko-when-they-cry-question-arcs",
      images: %{
        small:
          "https://images.kaguya.io/visual_novels/019cba59-2011-7d71-ac30-19b21e0862d4-128w.webp",
        medium:
          "https://images.kaguya.io/visual_novels/019cba59-2011-7d71-ac30-19b21e0862d4-256w.webp",
        large:
          "https://images.kaguya.io/visual_novels/019cba59-2011-7d71-ac30-19b21e0862d4-512w.webp",
        xl:
          "https://images.kaguya.io/visual_novels/019cba59-2011-7d71-ac30-19b21e0862d4-1024w.webp"
      }
    },
    %{
      title: "Witch on the Holy Night",
      slug: "witch-on-the-holy-night",
      images: %{
        small:
          "https://images.kaguya.io/visual_novels/019c51b8-b11a-7f85-b30b-d176219b357a-128w.webp",
        medium:
          "https://images.kaguya.io/visual_novels/019c51b8-b11a-7f85-b30b-d176219b357a-256w.webp",
        large:
          "https://images.kaguya.io/visual_novels/019c51b8-b11a-7f85-b30b-d176219b357a-512w.webp",
        xl:
          "https://images.kaguya.io/visual_novels/019c51b8-b11a-7f85-b30b-d176219b357a-1024w.webp"
      }
    },
    %{
      title: "Slow Damage",
      slug: "slow-damage",
      images: %{
        small:
          "https://images.kaguya.io/visual_novels/019c51bc-fd0f-7866-acdc-f5a2eed31136-128w.webp",
        medium:
          "https://images.kaguya.io/visual_novels/019c51bc-fd0f-7866-acdc-f5a2eed31136-256w.webp",
        large:
          "https://images.kaguya.io/visual_novels/019c51bc-fd0f-7866-acdc-f5a2eed31136-512w.webp",
        xl:
          "https://images.kaguya.io/visual_novels/019c51bc-fd0f-7866-acdc-f5a2eed31136-1024w.webp"
      }
    },
    %{
      title: "TAISHO x ALICE",
      slug: "taisho-x-alice",
      images: %{
        small:
          "https://images.kaguya.io/visual_novels/019c51bd-4c0a-77b3-be3e-df6d7732d1db-128w.webp",
        medium:
          "https://images.kaguya.io/visual_novels/019c51bd-4c0a-77b3-be3e-df6d7732d1db-256w.webp",
        large:
          "https://images.kaguya.io/visual_novels/019c51bd-4c0a-77b3-be3e-df6d7732d1db-512w.webp",
        xl:
          "https://images.kaguya.io/visual_novels/019c51bd-4c0a-77b3-be3e-df6d7732d1db-1024w.webp"
      }
    }
  ]

  @stats [
    %{value: "105K", label: "logged"},
    %{value: "60K", label: "visual novels"},
    %{value: "25K", label: "ratings"},
    %{value: "730", label: "reviews"}
  ]

  @showcases [
    %{
      title: "Personal lists for everything",
      body:
        "Rank your favorites, plan your year, share the stuff you think more people should read.",
      image: "https://images.kaguya.io/ui/home/lists-featured.webp",
      alt: "A list on Kaguya titled 2026 goals",
      reverse?: false
    },
    %{
      title: "Show your taste",
      body: "Pin your favorites, show your ratings, let people know what kind of reader you are.",
      image: "https://images.kaguya.io/ui/home/featured-profile.webp",
      alt: "A Kaguya profile showing favorite VNs, bio, and reading stats",
      reverse?: true
    },
    %{
      title: "Get your VN reading stats",
      body: "See your reading history, hours logged, and how your taste has evolved over time.",
      image: "https://images.kaguya.io/ui/home/stats-charts.webp",
      alt: "Reading stats showing titles and hours read over time",
      reverse?: false
    },
    %{
      title: "Already on VNDB?",
      body: "Import your list, keep your ratings, pick up right where you left off.",
      image: "https://images.kaguya.io/ui/home/import-summary.webp",
      alt: "VNDB import summary showing matched visual novels and reading status",
      reverse?: true
    }
  ]

  def mount(_params, _session, %{assigns: %{current_user: current_user}} = socket)
      when not is_nil(current_user) do
    {:ok, redirect(socket, to: ~p"/lists")}
  end

  def mount(_params, _session, socket) do
    {:ok, assign_landing(socket)}
  end

  def assign_landing(socket) do
    socket
    |> assign(:page_title, @page_title)
    |> assign(:meta_description, @description)
    |> assign(:canonical_url, "https://kaguya.io")
    |> assign(:og_title, @page_title)
    |> assign(:og_description, @description)
    |> assign(:og_image, @og_image)
    |> assign(:og_image_width, 1200)
    |> assign(:og_image_height, 630)
    |> assign(:og_image_alt, @og_image_alt)
    |> assign(:twitter_title, @page_title)
    |> assign(:twitter_description, @description)
    |> assign(:twitter_image, @og_image)
    |> assign(:preload_hero_image, @hero_image)
    |> assign(:nav_transparent, true)
    |> assign(:hero_image, @hero_image)
    |> assign(:covers, @covers)
    |> assign(:stats, @stats)
    |> assign(:showcases, @showcases)
  end

  def render(assigns) do
    ~H"""
    <.landing_page
      hero_image={@hero_image}
      covers={@covers}
      stats={@stats}
      showcases={@showcases}
    />
    """
  end

  attr :hero_image, :string, required: true
  attr :covers, :list, required: true
  attr :stats, :list, required: true
  attr :showcases, :list, required: true

  def landing_page(assigns) do
    ~H"""
    <div class="w-full pb-32 lg:-mt-[72px] lg:pb-40">
      <section class="relative w-full">
        <div
          class="pointer-events-none absolute inset-x-0 top-0 z-0 aspect-video overflow-hidden lg:hidden"
          aria-hidden="true"
        >
          <div
            class="size-full bg-cover bg-center"
            style={"background-image: url(#{@hero_image})"}
          >
          </div>
          <div
            class="pointer-events-none absolute inset-0"
            style={"background-image: #{mobile_backdrop_gradient()}"}
          >
          </div>
        </div>

        <div
          class="pointer-events-none absolute inset-x-0 top-0 z-0 hidden h-[675px] overflow-hidden lg:block"
          aria-hidden="true"
        >
          <div
            class="absolute inset-x-0 top-0 z-1 h-[135px] opacity-70"
            style={"background-image: #{top_gradient()}"}
          >
          </div>
          <div class="absolute inset-y-0 left-1/2 w-[1125px] -translate-x-1/2">
            <div
              class="absolute inset-0 bg-cover"
              style={"background-image: url(#{@hero_image}); background-position: center 20%;"}
            >
            </div>
            <div
              class="pointer-events-none absolute inset-0 bg-no-repeat"
              style={"background-image: #{side_gradient()}, #{bottom_gradient()}"}
            >
            </div>
          </div>
        </div>

        <div class="pointer-events-none absolute inset-y-0 left-1/2 z-20 hidden w-[1125px] -translate-x-1/2 xl:block">
          <.link
            navigate="/vn/full-metal-daemon-muramasa"
            class="hover:text-foreground-primary text-foreground-quaternary text-style-body1Regular pointer-events-auto absolute top-[35%] -right-5 max-h-[300px] -translate-y-1/2 rotate-180 truncate transition-colors duration-300"
            style="writing-mode: vertical-rl"
          >
            Full Metal Daemon Muramasa
          </.link>
        </div>

        <div class="relative z-10 flex flex-col items-center px-6 pt-[calc(100vw*9/16)] pb-16 text-center lg:pt-[542px] lg:pb-20">
          <h1
            class="text-[28px] leading-[1.3] font-bold text-white md:text-[30px] lg:text-[46px] lg:leading-[1.1]"
            style="font-family: var(--font-fraunces)"
          >
            The social tracker for VN readers.
          </h1>

          <div class="mt-8 lg:mt-10">
            <a
              href="/signup"
              class="active:bg-button-background-brand-pressed bg-button-background-brand-default hover:bg-button-background-brand-hover text-button-text-on-brand flex h-[42px] w-fit items-center rounded-[4px] px-5 text-base font-medium transition"
            >
              Get started
            </a>
          </div>

          <div class="mt-10 flex items-center justify-center gap-6 sm:gap-10 lg:mt-12 lg:gap-14">
            <div :for={stat <- @stats} class="text-center">
              <div class="text-[22px] leading-none font-semibold text-white sm:text-[26px] lg:text-[32px]">
                {stat.value}
              </div>
              <div class="text-foreground-tertiary mt-1.5 text-[13px] lg:text-[14px]">
                {stat.label}
              </div>
            </div>
          </div>
        </div>
      </section>

      <section class="w-full px-4 sm:px-6 md:px-8 lg:px-0">
        <div class="grid grid-cols-4 gap-x-2 sm:hidden">
          <div :for={cover <- Enum.take(@covers, 4)}>
            <.landing_cover cover={cover} sizes="106px" class="rounded-[2px]" />
          </div>
        </div>

        <div class="mx-auto hidden max-w-[1168px] grid-cols-6 gap-4 sm:grid">
          <.landing_cover
            :for={cover <- @covers}
            cover={cover}
            sizes="calc((1168px - 5 * 16px) / 6)"
            class="rounded-[4px]"
          />
        </div>
      </section>

      <div class="w-full px-6 md:px-8 lg:px-[136px]">
        <div class="mx-auto max-w-[1168px]">
          <section
            :for={showcase <- @showcases}
            class={[
              "flex flex-col items-center gap-10 pt-24 lg:gap-20",
              "lg:pt-40 first:lg:pt-36",
              if(Map.get(showcase, :reverse?), do: "lg:flex-row-reverse", else: "lg:flex-row")
            ]}
          >
            <div class="w-full shrink-0 lg:w-[42%]">
              <h2
                class="text-[32px] leading-[1.15] text-white lg:text-[44px]"
                style="font-family: var(--font-fraunces)"
              >
                {showcase.title}
              </h2>
              <p class="text-foreground-secondary mt-5 text-[17px] leading-[1.7] lg:text-[18px]">
                {showcase.body}
              </p>
            </div>
            <div class="w-full lg:w-[58%]">
              <img src={showcase.image} alt={showcase.alt} class="w-full rounded-lg" />
            </div>
          </section>
        </div>
      </div>
    </div>
    """
  end

  attr :cover, :map, required: true
  attr :sizes, :string, required: true
  attr :class, :string, default: "rounded-[4px]"

  defp landing_cover(assigns) do
    ~H"""
    <.link navigate={"/vn/#{@cover.slug}"} title={@cover.title} class="block">
      <img
        src={@cover.images.medium}
        srcset={cover_srcset(@cover)}
        sizes={@sizes}
        alt={@cover.title}
        class={["bg-surface-elevated aspect-1/1.5 w-full object-cover object-center", @class]}
        loading="lazy"
      />
    </.link>
    """
  end

  defp cover_srcset(%{images: images}) do
    [
      "#{images.small} 128w",
      "#{images.medium} 256w",
      "#{images.large} 512w",
      "#{images.xl} 1024w"
    ]
    |> Enum.join(", ")
  end

  defp mobile_backdrop_gradient do
    "linear-gradient(to bottom, rgb(var(--surface-base) / 0), rgb(var(--surface-base) / 0) 50%, rgb(var(--surface-base) / 0.75), rgb(var(--surface-base)))"
  end

  defp top_gradient do
    "linear-gradient(to bottom, rgb(var(--surface-base)), rgb(var(--surface-base) / 0.945) 16.56%, rgb(var(--surface-base) / 0.8) 30.85%, rgb(var(--surface-base) / 0.608) 43.77%, rgb(var(--surface-base) / 0.392) 56.23%, rgb(var(--surface-base) / 0.2) 69.15%, rgb(var(--surface-base) / 0.055) 83.44%, rgb(var(--surface-base) / 0) 100%)"
  end

  defp side_gradient do
    "linear-gradient(to right, rgb(var(--surface-base)) 0%, rgb(var(--surface-base) / 0.984) 0.97%, rgb(var(--surface-base) / 0.945) 2.07833333%, rgb(var(--surface-base) / 0.882) 3.29666667%, rgb(var(--surface-base) / 0.804) 4.60166667%, rgb(var(--surface-base) / 0.71) 5.96666667%, rgb(var(--surface-base) / 0.608) 7.5%, rgb(var(--surface-base) / 0.5) 9.16666667%, rgb(var(--surface-base) / 0.396) 10.16%, rgb(var(--surface-base) / 0.294) 11.505%, rgb(var(--surface-base) / 0.204) 12.78%, rgb(var(--surface-base) / 0.12) 13.95833333%, rgb(var(--surface-base) / 0.06) 15.01666667%, rgb(var(--surface-base) / 0.016) 15.92833333%, rgb(var(--surface-base) / 0) 16.66666667%, rgb(var(--surface-base) / 0) 83.33333333%, rgb(var(--surface-base) / 0.016) 84.07166667%, rgb(var(--surface-base) / 0.06) 84.98333333%, rgb(var(--surface-base) / 0.12) 86.04166667%, rgb(var(--surface-base) / 0.204) 87.22%, rgb(var(--surface-base) / 0.294) 88.495%, rgb(var(--surface-base) / 0.396) 89.84%, rgb(var(--surface-base) / 0.5) 90.83333333%, rgb(var(--surface-base) / 0.608) 92.5%, rgb(var(--surface-base) / 0.71) 94.03333333%, rgb(var(--surface-base) / 0.804) 95.39833333%, rgb(var(--surface-base) / 0.882) 96.70333333%, rgb(var(--surface-base) / 0.945) 97.92166667%, rgb(var(--surface-base) / 0.984) 99.03%, rgb(var(--surface-base)) 100%)"
  end

  defp bottom_gradient do
    "linear-gradient(to top, rgb(var(--surface-base)) 0%, rgb(var(--surface-base)) 21.48148148%, rgb(var(--surface-base) / 0.984) 23.63703704%, rgb(var(--surface-base) / 0.945) 26.1%, rgb(var(--surface-base) / 0.882) 28.80740741%, rgb(var(--surface-base) / 0.804) 31.70740741%, rgb(var(--surface-base) / 0.71) 34.74074074%, rgb(var(--surface-base) / 0.608) 37.5%, rgb(var(--surface-base) / 0.5) 40.97407407%, rgb(var(--surface-base) / 0.396) 44.05925926%, rgb(var(--surface-base) / 0.294) 47.04814815%, rgb(var(--surface-base) / 0.204) 49.88148148%, rgb(var(--surface-base) / 0.12) 52.5%, rgb(var(--surface-base) / 0.06) 54.85185185%, rgb(var(--surface-base) / 0.016) 56.87777778%, rgb(var(--surface-base) / 0) 58.51851852%)"
  end
end
