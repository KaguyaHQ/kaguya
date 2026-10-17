defmodule KaguyaWeb.HomeLive.LandingStory do
  @moduledoc """
  Signed-out landing story below the hero.

    * Four chapters (lists, profile, stats, import) scroll on the left while
      one app window stays pinned on the right and bleeds off the screen edge.
    * One VN (The House in Fata Morgana) travels between the windows: it is
      on eightpunch's list (re-ranked from #14 to #3 as you scroll), Vas's
      top favorite, and in Vas's biggest year. The other favorites shown are
      picked for how they look together, not taken from Vas's profile.
    * Each chapter is lit by a blurred CG and tints the page to match.
    * Ends on a drifting wall of covers with the sign-up call to action.

  Content is a curated snapshot of real Kaguya data, hardcoded like the
  hero covers so the public page issues no queries. The `LandingStory` hook
  owns all motion; below `lg` the windows sit under their chapter text.
  """

  use KaguyaWeb, :html

  alias Kaguya.Users
  alias Kaguya.VisualNovels

  @traveler_slug "the-house-in-fata-morgana"

  @list_entries [
    %{
      slug: "collar-x-malice",
      title: "Collar x Malice",
      image_id: "019c51bd-163d-7801-9f15-64277f948370"
    },
    %{
      slug: "folie-fatale-yandere-otoko-ni-otosareru",
      title: "Folie Fatale ~Yandere Otoko ni Otosareru~",
      image_id: "019c51ba-61b4-7556-b748-15bc8c080f7d"
    },
    %{slug: "shizuku", title: "Shizuku", image_id: "019cba58-f64f-76c5-ab32-d924c7cc6559"},
    %{
      slug: "9-nine-episode-1",
      title: "9-nine-:Episode 1",
      image_id: "019c51bc-e824-7b58-9278-879f04967c80"
    },
    %{
      slug: "nekopara-vol-1",
      title: "NEKOPARA Vol. 1",
      image_id: "019c51bd-572c-7e8e-a5dd-1e916d738ffb"
    },
    %{
      slug: "how-to-make-a-perfect-girlfriend",
      title: "How To Make a Perfect Girlfriend",
      image_id: "019c51bb-f315-76cb-8ba4-f061b25e532b"
    },
    %{
      slug: "wonderful-everyday-diskontinuierliches-dasein",
      title: "Wonderful Everyday ~Diskontinuierliches Dasein~",
      image_id: "019c51bb-c3fd-74ec-9ea5-9629b6da9a84"
    },
    %{
      slug: "higurashi-when-they-cry-question-arcs",
      title: "Higurashi When They Cry - Question Arcs",
      image_id: "019cba58-a821-7cf9-aaad-51f63122a65e"
    },
    %{
      slug: "fate-hollow-ataraxia",
      title: "Fate/hollow ataraxia",
      image_id: "019cba58-a89a-78a5-965b-1167f2a4e72b"
    },
    %{slug: "aoi-tori", title: "Aoi Tori", image_id: "019c51bc-b8c4-7590-871e-c5d11115aedc"},
    %{
      slug: "raging-loop",
      title: "Raging Loop",
      image_id: "019c51bc-bffc-7d5f-b791-60461915521d"
    },
    %{slug: "suika", title: "Suika", image_id: "019c51b8-6d21-7e5d-9b0a-1405f15c5bb9"},
    %{
      slug: "aokana-four-rhythms-across-the-blue-extra2",
      title: "Aokana - Four Rhythms Across the Blue - EXTRA2",
      image_id: "019c51bc-bb23-79c7-91b1-6abda4b20d47"
    },
    %{
      slug: "the-house-in-fata-morgana",
      title: "The House in Fata Morgana",
      image_id: "019c51bd-a728-7845-979e-a085589a54bd"
    },
    %{
      slug: "doki-doki-literature-club",
      title: "Doki Doki Literature Club!",
      image_id: "019cba59-36c9-73a8-8bb4-49ab30d046cb"
    },
    %{
      slug: "planetarian-dream-of-little-star",
      title: "planetarian ~Dream of Little Star~",
      image_id: "019c51bb-899e-79a5-8929-ada02414d93d"
    },
    %{
      slug: "the-shell-part-iii-paradiso",
      title: "The Shell Part III: Paradiso",
      image_id: "019c51bd-31db-7a4f-ac14-521116bac5f0"
    },
    %{slug: "air", title: "AIR", image_id: "019c51bb-5fdc-7cdb-945f-add5332089f0"},
    %{
      slug: "you-and-me-and-her-a-love-story",
      title: "YOU and ME and HER: A Love Story",
      image_id: "019cba58-5b35-7fa6-8a9c-e5479e329ffa"
    }
  ]

  @favorites [
    %{
      slug: "the-house-in-fata-morgana",
      title: "The House in Fata Morgana",
      image_id: "019c51bd-a728-7845-979e-a085589a54bd"
    },
    %{
      slug: "full-metal-daemon-muramasa",
      title: "Full Metal Daemon Muramasa",
      image_id: "019cba58-a759-7a8d-a189-b235997a52bd"
    },
    %{
      slug: "tsukihime-a-piece-of-blue-glass-moon",
      title: "TSUKIHIME -A piece of blue glass moon-",
      image_id: "019c51bd-1dc6-77bd-8a7f-f8244915091c"
    },
    %{
      slug: "witch-on-the-holy-night",
      title: "Witch on the Holy Night",
      image_id: "019c51b8-b11a-7f85-b30b-d176219b357a"
    }
  ]

  @import_entries [
    %{
      slug: "angel-beats-1st-beat",
      title: "Angel Beats! -1st beat-",
      image_id: "019c51bd-8767-7c86-a576-2aa38d33536a"
    },
    %{
      slug: "mirai-nostalgia",
      title: "Mirai Nostalgia",
      image_id: "019c51b8-cc46-7735-afda-4349668661d2"
    },
    %{
      slug: "daitoshokan-no-hitsujikai",
      title: "Daitoshokan no Hitsujikai",
      image_id: "019c51b8-a4a4-7507-97c4-3778c2dc0758"
    },
    %{slug: "narcissu", title: "narcissu", image_id: "019c51bd-e583-752f-8e95-6263bce70dd0"},
    %{
      slug: "tomodachi-ijou-koibito-miman-no-ryuusenkei",
      title: "Tomodachi Ijou Koibito Miman no Ryuusenkei",
      image_id: "019c51bd-1be3-74db-886b-5f923534ce01"
    },
    %{
      slug: "little-busters",
      title: "Little Busters!",
      image_id: "019c51ba-4dff-71b2-954c-beac247f0081"
    },
    %{
      slug: "the-fruit-of-grisaia",
      title: "The Fruit of Grisaia",
      image_id: "019c51ba-23f4-7458-8322-97064ad861cb"
    },
    %{
      slug: "robotics-notes",
      title: "ROBOTICS;NOTES",
      image_id: "019cba58-a6ba-727d-ae09-adb646a1a499"
    },
    %{
      slug: "amatsutsumi",
      title: "Amatsutsumi",
      image_id: "019c51bd-0251-7e31-8d75-7d9ca08d8af4"
    },
    %{
      slug: "chaos-child",
      title: "CHAOS;CHILD",
      image_id: "019cba57-c53f-7028-9f7f-3a663916a5ab"
    },
    %{slug: "clannad", title: "CLANNAD", image_id: "019c51bb-12b1-79b4-ab69-71728a3f4ea6"},
    %{slug: "air", title: "AIR", image_id: "019c51bb-5fdc-7cdb-945f-add5332089f0"},
    %{
      slug: "chaos-head-noah",
      title: "CHAOS;HEAD NOAH",
      image_id: "019c51bc-a062-7f24-9b5a-b9ea58198d12"
    },
    %{
      slug: "natsuyume-nagisa",
      title: "Natsuyume Nagisa",
      image_id: "019c51bd-258b-7973-b5ce-e4e6a0712ac0"
    },
    %{
      slug: "natsuiro-kokoro-log",
      title: "Natsuiro Kokoro Log",
      image_id: "019c51bd-0723-715b-bae2-a567868d9dd2"
    },
    %{
      slug: "sharin-no-kuni-the-girl-among-the-sunflowers",
      title: "Sharin no Kuni: The Girl Among the Sunflowers",
      image_id: "019c51b9-6348-764e-b7c5-224cb4ed7561"
    }
  ]

  @wall_covers [
    %{
      slug: "steins-gate",
      title: "Steins;Gate",
      image_id: "019c51bc-e2d6-73b9-98b4-86bc7bad9ce2"
    },
    %{
      slug: "umineko-when-they-cry-answer-arcs",
      title: "Umineko When They Cry - Answer Arcs",
      image_id: "019c51bc-b84b-7d8a-b9a8-bdfb54a46328"
    },
    %{
      slug: "utawarerumono-mask-of-truth",
      title: "Utawarerumono: Mask of Truth",
      image_id: "019d1fd6-821e-7048-a9f9-9264ec194908"
    },
    %{
      slug: "umineko-when-they-cry-question-arcs",
      title: "Umineko When They Cry - Question Arcs",
      image_id: "019cba59-2011-7d71-ac30-19b21e0862d4"
    },
    %{
      slug: "higurashi-when-they-cry-answer-arcs",
      title: "Higurashi When They Cry - Answer Arcs",
      image_id: "019cba57-92a6-7b13-9927-d9730a562396"
    },
    %{
      slug: "tsukihime-a-piece-of-blue-glass-moon",
      title: "TSUKIHIME -A piece of blue glass moon-",
      image_id: "019c51bd-1dc6-77bd-8a7f-f8244915091c"
    },
    %{
      slug: "the-house-in-fata-morgana",
      title: "The House in Fata Morgana",
      image_id: "019c51bd-a728-7845-979e-a085589a54bd"
    },
    %{slug: "clannad", title: "CLANNAD", image_id: "019c51bb-12b1-79b4-ab69-71728a3f4ea6"},
    %{
      slug: "witch-on-the-holy-night",
      title: "Witch on the Holy Night",
      image_id: "019c51b8-b11a-7f85-b30b-d176219b357a"
    },
    %{
      slug: "higurashi-when-they-cry-question-arcs",
      title: "Higurashi When They Cry - Question Arcs",
      image_id: "019cba58-a821-7cf9-aaad-51f63122a65e"
    },
    %{
      slug: "the-house-in-fata-morgana-a-requiem-for",
      title: "The House in Fata Morgana: A Requiem for Innocence",
      image_id: "019c51bd-0df4-7e0c-bfbf-d86e04506cd2"
    },
    %{slug: "rewrite", title: "Rewrite", image_id: "019c51b8-b6f5-7f8b-a8ba-2d9e47249200"},
    %{
      slug: "summer-pockets",
      title: "Summer Pockets",
      image_id: "019c51bc-d67b-7c67-865e-330989ed6415"
    },
    %{
      slug: "chaos-child",
      title: "CHAOS;CHILD",
      image_id: "019cba57-c53f-7028-9f7f-3a663916a5ab"
    },
    %{
      slug: "flowers-le-volume-sur-ete",
      title: "Flowers -Le volume sur ete-",
      image_id: "019c51bd-5c21-793e-a1b4-59ff1a49cfe4"
    },
    %{
      slug: "utawarerumono-mask-of-deception",
      title: "Utawarerumono: Mask of Deception",
      image_id: "019d1fd4-5958-760d-aab7-541837cf7ea7"
    },
    %{
      slug: "999-nine-hours-nine-persons-nine-doors",
      title: "999: Nine Hours, Nine Persons, Nine Doors",
      image_id: "019d1fd5-89c7-742d-b9ba-1178f4a517eb"
    },
    %{
      slug: "remember11-the-age-of-infinity",
      title: "Remember11 -the age of infinity-",
      image_id: "019cba58-f403-722b-b312-700ffbfde551"
    },
    %{
      slug: "your-turn-to-die-death-game-by-majority",
      title: "Your Turn To Die -Death Game By Majority-",
      image_id: "019c51bc-4d31-7fc6-9a88-c834ca0e167c"
    },
    %{
      slug: "collar-x-malice",
      title: "Collar x Malice",
      image_id: "019c51bd-163d-7801-9f15-64277f948370"
    },
    %{
      slug: "rose-guns-days",
      title: "Rose Guns Days",
      image_id: "019c51b8-7251-76eb-867f-c2b12fc88ca1"
    },
    %{
      slug: "stella-of-the-end",
      title: "Stella of The End",
      image_id: "019c51bb-f2c3-70dc-af9a-d17793f420c6"
    },
    %{
      slug: "symphonic-rain",
      title: "Symphonic Rain",
      image_id: "019c51bb-373c-7a07-b812-bc1b83fb23e9"
    },
    %{slug: "seabed", title: "SeaBed", image_id: "019c51bc-f80c-7491-b4d0-b35e941d0c3e"},
    %{
      slug: "danganronpa-2-goodbye-despair",
      title: "Danganronpa 2: Goodbye Despair",
      image_id: "019d1fd5-1d4a-72c8-94a3-6222fbb88bdb"
    },
    %{
      slug: "steins-gate-0",
      title: "STEINS;GATE 0",
      image_id: "019c51bd-2fb9-760e-a233-29368bcfb64c"
    },
    %{
      slug: "the-hundred-line-last-defense-academy",
      title: "The Hundred Line -Last Defense Academy-",
      image_id: "019d1fd7-c0d8-7c0b-9ccc-69368df12464"
    },
    %{
      slug: "va-11-hall-a",
      title: "VA-11 HALL-A",
      image_id: "019c51bd-0224-75e4-8489-2ee12a060f10"
    },
    %{
      slug: "hakuoki-demon-of-the-fleeting-blossom",
      title: "Hakuoki ~Demon of the Fleeting Blossom~",
      image_id: "019c51bd-2fa4-7b6a-8a68-8eab7c5753d3"
    },
    %{
      slug: "mystic-messenger",
      title: "Mystic Messenger",
      image_id: "019c51bd-1d2a-73e3-b6d2-1ef5f47b0438"
    },
    %{
      slug: "raging-loop",
      title: "Raging Loop",
      image_id: "019c51bc-bffc-7d5f-b791-60461915521d"
    },
    %{
      slug: "angel-beats-1st-beat",
      title: "Angel Beats! -1st beat-",
      image_id: "019c51bd-8767-7c86-a576-2aa38d33536a"
    },
    %{
      slug: "ai-the-somnium-files",
      title: "AI: THE SOMNIUM FILES",
      image_id: "019d1fd2-a48a-7833-b219-df9201292dee"
    },
    %{
      slug: "planetarian-dream-of-little-star",
      title: "planetarian ~Dream of Little Star~",
      image_id: "019c51bb-899e-79a5-8929-ada02414d93d"
    },
    %{
      slug: "chaos-head-noah",
      title: "CHAOS;HEAD NOAH",
      image_id: "019c51bc-a062-7f24-9b5a-b9ea58198d12"
    },
    %{
      slug: "root-double-before-crime-after-days",
      title: "Root Double -Before Crime * After Days-",
      image_id: "019c51ba-4dff-77af-aaf8-bb6880cbd2d3"
    },
    %{
      slug: "ciconia-when-they-cry",
      title: "Ciconia When They Cry",
      image_id: "019c51bc-68c5-7b5c-b1bb-b7762e68d3c8"
    },
    %{
      slug: "atri-my-dear-moments",
      title: "ATRI -My Dear Moments-",
      image_id: "019c51bc-247f-7c76-9eee-4d2ac941df06"
    },
    %{
      slug: "slay-the-princess",
      title: "Slay the Princess",
      image_id: "019c51bb-4935-7ab0-ab71-bf62c49b1773"
    },
    %{slug: "island", title: "ISLAND", image_id: "019c51bd-0bad-74cb-a6ea-1c54da61c745"},
    %{
      slug: "robotics-notes",
      title: "ROBOTICS;NOTES",
      image_id: "019cba58-a6ba-727d-ae09-adb646a1a499"
    },
    %{
      slug: "fault-milestone-two-side-above",
      title: "fault - milestone two side: above",
      image_id: "019c51bd-5e89-7c6a-8cc0-2e01fa10b920"
    },
    %{
      slug: "danganronpa-v3-killing-harmony",
      title: "Danganronpa V3: Killing Harmony",
      image_id: "019d1fda-28f2-7e14-a5ac-6cdd2466ab8d"
    },
    %{
      slug: "paranormasight-the-seven-mysteries-of-honjo",
      title: "PARANORMASIGHT: The Seven Mysteries of Honjo",
      image_id: "019c51ba-e20c-7630-945c-83bb88b4d983"
    },
    %{
      slug: "marco-the-galaxy-dragon",
      title: "Marco & The Galaxy Dragon",
      image_id: "019c51bc-3372-7448-b049-9c64e10c9e92"
    },
    %{
      slug: "higurashi-no-naku-koro-ni-rei",
      title: "Higurashi no Naku Koro ni Rei",
      image_id: "019cba57-c58c-73a8-991c-b91cf7c35271"
    },
    %{
      slug: "true-remembrance",
      title: "TRUE REMEMBRANCE",
      image_id: "019c51bd-dd47-7334-b3a2-2552ecab7983"
    },
    %{
      slug: "corpse-party",
      title: "Corpse Party",
      image_id: "019d1fd8-6e55-78c3-a6b4-4dbb2cc7b018"
    },
    %{
      slug: "flowers-le-volume-sur-printemps",
      title: "Flowers -Le volume sur printemps-",
      image_id: "019c51bd-7add-7e4a-990e-139f39563aa2"
    },
    %{
      slug: "world-end-economica",
      title: "WORLD END ECONOMiCA",
      image_id: "019c51b8-c04c-743a-8be1-4ba56936d7f4"
    },
    %{
      slug: "melty-blood",
      title: "MELTY BLOOD",
      image_id: "019d1fd2-f214-7b69-b18f-23723440ce04"
    },
    %{
      slug: "higanbana-no-saku-yoru-ni-dai-ichi-ya",
      title: "Higanbana no Saku Yoru ni - Dai Ichi Ya",
      image_id: "019c51b8-b6ee-7f3e-991b-19e09dce237f"
    },
    %{
      slug: "lucy-the-eternity-she-wished-for",
      title: "Lucy -The Eternity She Wished For-",
      image_id: "019c51bd-3991-73ad-893c-dd1f14f5a3e0"
    }
  ]

  @list %{
    title: "2026 goals",
    path: "/@eightpunch/list/2026-goals",
    owner: "pb",
    owner_path: "/@eightpunch",
    owner_avatar_id: "019ba929-54f0-70d2-8e54-7fdc952f8d46",
    updated: "Updated Jul 23",
    description: "lofty but i will try! some are in progress and i just want to finish this year"
  }

  @profile %{
    name: "Vas",
    username: "vas",
    avatar_id: "019b9e15-527a-775e-963e-d5c4877ddd37",
    bio:
      "Writing, music and humor appeal to me most. I also like it when it has a mix of genres in the same work.",
    counts: [{"91", "VNs"}, {"6", "Lists"}, {"16", "Followers"}, {"7", "Following"}],
    activity: [
      %{verb: "Rated", title: "planetarian ~Dream of Little Star~", stars: 3, date: "Sep 24"}
    ]
  }

  @reading_years %{
    labels: ["2023", "2024", "2025", "2026"],
    hours: [404, 13, 251, 223],
    titles: [14, 3, 4, 6]
  }

  @chapters [
    %{
      key: "lists",
      label: "Lists",
      title: "Rank them. Defend the ranking.",
      body:
        "Make lists for anything: an all-time top ten, this year's backlog, the ones you push on every new reader."
    },
    %{
      key: "profile",
      label: "Profile",
      title: "Your taste, on display.",
      body:
        "Pin your favorites, set a banner from a CG you love, and let people see what you rate highly."
    },
    %{
      key: "stats",
      label: "Stats",
      title: "Every late night, counted.",
      body:
        "Hours logged, titles finished, and the years you read the most. It all adds up as you read."
    },
    %{
      key: "import",
      label: "Import",
      title: "Bring your VNDB history. All of it.",
      body:
        "Ratings, statuses and labels come with you, so you pick up exactly where you left off."
    }
  ]

  def story(assigns) do
    assigns =
      assigns
      |> assign(:chapters, @chapters)
      |> assign(:glows, glows())
      |> assign(:traveler, traveler())
      |> assign(:viewer_avatar, avatar_url(@profile.avatar_id))

    ~H"""
    <section
      id="landing-story"
      phx-hook="LandingStory"
      phx-update="ignore"
      class="landing-story px-6 md:px-8"
      data-active="lists"
      aria-label="What you can do on Kaguya"
    >
      <div class="landing-ambient" aria-hidden="true">
        <img :for={{key, src} <- @glows} data-for={key} src={src} alt="" loading="lazy" />
      </div>

      <div class="landing-story-grid mx-auto max-w-[1168px]">
        <div>
          <article :for={chapter <- @chapters} class="landing-chapter" data-chapter={chapter.key}>
            <span class="landing-chapter-label text-style-captionMedium">{chapter.label}</span>
            <h2 class="landing-chapter-title">{chapter.title}</h2>
            <p class="landing-chapter-body">{chapter.body}</p>
            <.panel key={chapter.key} viewer_avatar={@viewer_avatar} />
          </article>
        </div>

        <div class="landing-stage-col" data-stage-col>
          <div class="landing-stage" data-stage>
            <div class="landing-traveler" data-traveler aria-hidden="true">
              <img src={@traveler.src} alt="" />
            </div>
          </div>
        </div>
      </div>
    </section>
    """
  end

  def cover_wall(assigns) do
    assigns = assign(assigns, :rows, wall_rows())

    ~H"""
    <section class="landing-wall" aria-labelledby="landing-wall-title">
      <div class="landing-wall-rows" aria-hidden="true">
        <div :for={{row, index} <- Enum.with_index(@rows)} class="landing-wall-row" data-row={index}>
          <img
            :for={vn <- row ++ row}
            src={VisualNovels.build_image_urls(vn.image_id).medium}
            alt=""
            loading="lazy"
          />
        </div>
      </div>
      <div class="landing-wall-copy">
        <h2 id="landing-wall-title" class="landing-wall-title">
          Your next favorite is in here somewhere.
        </h2>
        <p class="text-foreground-secondary text-style-body1Regular max-w-[46ch]">
          Over 60,000 visual novels, rated and reviewed by people who actually read them.
        </p>
        <a
          href="/signup"
          class="active:bg-button-background-brand-pressed bg-button-background-brand-default hover:bg-button-background-brand-hover text-button-text-on-brand flex h-[42px] w-fit items-center rounded-[4px] px-5 text-base font-medium transition"
        >
          Get started
        </a>
      </div>
    </section>
    """
  end

  attr :key, :string, required: true
  attr :viewer_avatar, :string, required: true

  defp panel(%{key: "lists"} = assigns) do
    assigns =
      assigns
      |> assign(:list, @list)
      |> assign(:entries, Enum.with_index(@list_entries, 1))
      |> assign(:owner_avatar, avatar_url(@list.owner_avatar_id))

    ~H"""
    <div class="landing-panel" data-panel="lists">
      <.app_bar avatar={@viewer_avatar} />
      <div class="landing-panel-body">
        <.link navigate={@list.path} class="landing-list-title hover:underline">
          {@list.title}
        </.link>
        <div class="landing-byline text-style-body2Regular">
          <img src={@owner_avatar} alt="" class="landing-avatar-sm" />
          <.link navigate={@list.owner_path} class="text-foreground-primary">{@list.owner}</.link>
          <span aria-hidden="true">·</span>
          <span>{@list.updated}</span>
          <span aria-hidden="true">·</span>
          <span data-list-count>{length(@entries)} VNs</span>
        </div>
        <p class="text-foreground-primary text-style-body1Regular mt-3">{@list.description}</p>
        <ol class="landing-list-grid" data-list-grid>
          <li :for={{vn, rank} <- @entries}>
            <.panel_cover vn={vn} slot={vn.slug == traveler_slug() && "lists"} />
            <span class="landing-rank">{rank}</span>
          </li>
        </ol>
        <div class="landing-toast" data-toast>Moved {traveler_title()} to #3</div>
      </div>
      <div class="landing-panel-fade"></div>
    </div>
    """
  end

  defp panel(%{key: "profile"} = assigns) do
    assigns =
      assigns
      |> assign(:profile, @profile)
      |> assign(:favorites, @favorites)

    ~H"""
    <div class="landing-panel landing-panel-profile" data-panel="profile">
      <.app_bar avatar={@viewer_avatar} />
      <div class="landing-panel-body">
        <div class="landing-banner">
          <img
            src={~p"/images/landing/vas-banner.webp"}
            alt="Profile banner with a CG from The House in Fata Morgana"
            data-banner
          />
        </div>
        <div class="landing-profile-pad">
          <div class="landing-profile-head">
            <img src={@viewer_avatar} alt="" class="landing-avatar-lg" />
            <div class="pb-1.5">
              <.link navigate={"/@#{@profile.username}"} class="landing-profile-name">
                {@profile.name}
              </.link>
              <span class="text-foreground-tertiary text-style-body2Regular">
                @{@profile.username}
              </span>
            </div>
            <dl class="landing-profile-counts">
              <div :for={{value, label} <- @profile.counts}>
                <dt class="text-foreground-secondary text-style-captionRegular">{label}</dt>
                <dd>{value}</dd>
              </div>
            </dl>
          </div>
          <div class="landing-tabs text-style-body2Regular" aria-hidden="true">
            <span class="landing-tab-current">Profile</span>
            <span>Activity</span>
            <span>Library</span>
            <span>Lists</span>
          </div>
          <div class="landing-profile-cols">
            <div>
              <h4 class="landing-panel-heading">Favorite visual novels</h4>
              <div class="landing-favorites">
                <.panel_cover
                  :for={vn <- @favorites}
                  vn={vn}
                  slot={vn.slug == traveler_slug() && "profile"}
                />
              </div>
              <h4 class="landing-panel-heading mt-5">Recent activity</h4>
              <ul class="landing-activity text-style-body2Regular">
                <li :for={item <- @profile.activity}>
                  {item.verb} <b>{item.title}</b>
                  <span class="landing-stars" aria-label={"#{item.stars} out of 5 stars"}>
                    {String.duplicate("★", item.stars)}
                  </span>
                  <time>{item.date}</time>
                </li>
              </ul>
            </div>
            <div>
              <h4 class="landing-panel-heading">Bio</h4>
              <p class="text-foreground-primary text-style-body2Regular">{@profile.bio}</p>
            </div>
          </div>
        </div>
      </div>
      <div class="landing-panel-fade"></div>
    </div>
    """
  end

  defp panel(%{key: "stats"} = assigns) do
    assigns =
      assigns
      |> assign(:years, @reading_years)
      |> assign(:traveler, traveler())

    ~H"""
    <div class="landing-panel landing-panel-stats" data-panel="stats" data-mode="hours">
      <.app_bar avatar={@viewer_avatar} />
      <div class="landing-panel-body">
        <div class="landing-stats-top">
          <div>
            <h3 class="text-style-heading3Semibold">Reading by year</h3>
            <.link
              navigate="/@vas/stats"
              class="text-foreground-tertiary text-style-body2Regular hover:underline"
            >
              Vas's stats
            </.link>
          </div>
          <div class="landing-pills" role="group" aria-label="Chart metric">
            <button type="button" class="landing-pill" data-mode="hours" aria-pressed="true">
              Hours read
            </button>
            <button type="button" class="landing-pill" data-mode="titles" aria-pressed="false">
              Titles finished
            </button>
          </div>
        </div>
        <div class="landing-stats-mid">
          <div class="landing-bignum">
            <b data-bignum>{Enum.sum(@years.hours)}</b>
            <span data-bigunit class="text-foreground-secondary text-style-body1Regular">
              hours since 2023
            </span>
          </div>
          <div class="landing-peak">
            <.panel_cover vn={@traveler} slot="stats" class="w-11 shrink-0" />
            <div>
              <small class="text-foreground-tertiary text-style-captionMedium">
                Biggest year · 2023
              </small>
              <span class="text-foreground-primary text-style-body2Regular">
                404 hours, including {@traveler.title} ★★★★★
              </span>
            </div>
          </div>
        </div>
        <svg
          class="landing-chart"
          viewBox="0 0 640 300"
          role="img"
          aria-label="Hours read and titles finished per year, 2023 to 2026"
          data-chart
          data-labels={Jason.encode!(@years.labels)}
          data-hours={Jason.encode!(@years.hours)}
          data-titles={Jason.encode!(@years.titles)}
        >
          <defs>
            <linearGradient id="landing-chart-fill" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0" stop-opacity=".28" />
              <stop offset="1" stop-opacity="0" />
            </linearGradient>
          </defs>
          <path class="landing-chart-area" data-area />
          <path class="landing-chart-line" data-line />
          <g data-points></g>
          <g data-labels-group></g>
        </svg>
      </div>
    </div>
    """
  end

  defp panel(%{key: "import"} = assigns) do
    assigns = assign(assigns, :entries, @import_entries)

    ~H"""
    <div class="landing-panel" data-panel="import">
      <.app_bar avatar={@viewer_avatar} />
      <div class="landing-panel-body">
        <div class="landing-import-head">
          <span class="landing-vndb-mark" aria-hidden="true">DB</span>
          <h3 class="text-style-heading3Semibold">Import from VNDB</h3>
        </div>
        <div class="landing-import-row">
          <div class="landing-import-input">
            <span data-import-text></span><span class="landing-caret"></span>
          </div>
          <span class="landing-import-button">Import</span>
        </div>
        <div class="landing-progress"><i data-progress></i></div>
        <div class="landing-import-status text-style-body2Regular">
          <span data-import-label>Paste your VNDB profile link</span>
          <span data-import-count></span>
        </div>
        <div class="landing-import-grid">
          <.panel_cover :for={vn <- @entries} vn={vn} class="landing-import-cover" />
        </div>
        <div class="landing-import-done" data-import-done>
          <div>
            <h3 class="text-style-heading3Medium">Your library is ready.</h3>
            <dl class="landing-import-counts">
              <div :for={
                {value, label} <- [
                  {"59", "Visual novels"},
                  {"37", "Ratings"},
                  {"8", "Reviews"},
                  {"2", "Labels"}
                ]
              }>
                <dt class="text-foreground-secondary text-style-captionRegular">{label}</dt>
                <dd>{value}</dd>
              </div>
            </dl>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :avatar, :string, required: true

  defp app_bar(assigns) do
    ~H"""
    <div class="landing-app-bar" aria-hidden="true">
      <span class="landing-app-logo">Kaguya</span>
      <span class="landing-app-nav">Browse</span>
      <span class="landing-app-nav">Discussions</span>
      <span class="landing-app-search">
        <Lucide.search class="size-3.5" /> Search visual novels
      </span>
      <Lucide.bell class="landing-app-bell size-[18px]" />
      <img src={@avatar} alt="" class="landing-avatar-sm" />
    </div>
    """
  end

  attr :vn, :map, required: true
  attr :slot, :any, default: nil
  attr :class, :any, default: nil

  defp panel_cover(assigns) do
    assigns = assign(assigns, :images, VisualNovels.build_image_urls(assigns.vn.image_id))

    ~H"""
    <.link
      navigate={"/vn/#{@vn.slug}"}
      title={@vn.title}
      class={["landing-cover", @slot && "landing-cover-slot", @class]}
      data-slot={@slot}
    >
      <img
        src={@images.medium}
        srcset={"#{@images.medium} 256w, #{@images.large} 512w"}
        sizes="160px"
        alt={@vn.title}
        loading="lazy"
      />
    </.link>
    """
  end

  defp traveler_slug, do: @traveler_slug

  defp traveler_title, do: traveler().title

  defp traveler do
    vn = Enum.find(@favorites, &(&1.slug == @traveler_slug))
    Map.put(vn, :src, VisualNovels.build_image_urls(vn.image_id).large)
  end

  # One image per chapter for the blurred ambient light: Summer Pockets,
  # the profile banner, Sakura no Uta, and Fata Morgana.
  defp glows do
    [
      {"lists", screenshot_url("019c529f-c74a-795e-afee-512b2a04b7cf")},
      {"profile", ~p"/images/landing/vas-banner.webp"},
      {"stats", screenshot_url("019c52ae-9b07-751a-967e-74eb86eb09fd")},
      {"import", screenshot_url("019c52ad-8d89-7075-be64-a65d306380c1")}
    ]
  end

  defp screenshot_url(id), do: VisualNovels.build_screenshot_urls(id).medium

  defp avatar_url(id), do: Users.build_avatar_urls(id).small

  # Three rows with no cover shared between them; each row is doubled in the
  # template so the drift loops seamlessly.
  defp wall_rows do
    @wall_covers
    |> Enum.with_index()
    |> Enum.group_by(fn {_vn, i} -> rem(i, 3) end, fn {vn, _i} -> vn end)
    |> Enum.sort()
    |> Enum.map(fn {_row, covers} -> covers end)
  end
end
