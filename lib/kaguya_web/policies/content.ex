defmodule KaguyaWeb.Policies.Content do
  @moduledoc """
  Static content for the policy / about / FAQ pages.

  Keep this in sync when policy text changes.
  """

  @base_url "https://kaguya.io"

  @pages %{
    "help" => %{
      title: "Contributing to Kaguya",
      page_title: "Contributor help • Kaguya",
      description:
        "How to add visual novels, characters and producers, and improve existing entries.",
      body: """
      Found a VN that's missing? A character with the wrong name? You can help fix that. The catalog gets better when people who know these works add what they know.

      You need to sign in to add or edit entries. You don't need to know every detail about a work before you start. Add what you can verify and leave the rest for someone who can.

      ## What are you working on?

      - [Visual novels](/help/visual-novels): checking for duplicates, titles, descriptions and release details.
      - [Characters](/help/characters): names, VN appearances, roles and spoilers.
      - [Producers](/help/producers): companies, groups and their official links.
      - [Editing an entry](/help/editing): sources, summaries and revision history.
      - [Images and content](/help/images): covers, screenshots, sensitive content and reports.

      ## Before you add something

      Search for it first. Try the original title, the English title and any common alternative names. A translation or a different spelling doesn't necessarily mean it's a separate work.

      Gameplay hybrids belong in the catalog too. The [Content Policy](/content-policy) still applies. If an entry has been removed, ask about it before adding it again. A missing page isn't an invitation to get around a moderation decision.

      If you're unsure where something belongs, ask in [Feedback](/discussions/feedback). Include the title and an official source so we can understand what you're referring to.
      """
    },
    "help/visual-novels" => %{
      title: "Adding visual novels",
      page_title: "Adding visual novels • Kaguya",
      description: "A guide to titles, descriptions and the visual novel editor.",
      body: """
      Start by [searching the catalog](/search). Try a few names before creating a page. It saves you the work of adding everything twice, and keeps people's ratings and reviews together.

      Once you're sure it's missing, open [Add visual novel](/contribute/vn).

      ## Titles

      Add the title in its original language. Use the language field for the title you're entering, and the Romanized field for its Latin-script spelling where needed. Add an official translated title as another title, rather than replacing the original with it.

      Keep the spelling used by the work or its publisher. If you're unsure of a reading or translation, leave it for someone who knows. A guessed title makes the work harder to find.

      ## Description

      Give someone who hasn't read it an idea of the premise. Keep major reveals out of the description. Your verdict on whether it's good belongs in a review.

      Write a short description yourself, or use a source you're allowed to quote and credit it with a link. An official publisher page is a useful place to start. See [editing and sources](/help/editing).

      ## Details and relationships

      Use the release date, original language and development status you can verify. Don't invent a date or reading length to fill an empty field. An announcement isn't a finished release.

      A translated release or a new platform version usually belongs with the existing work. A remake may be a separate entry. If you're unsure, ask before creating a second page.

      When linking related VNs or producers, check the selected entry carefully. Similar names don't always mean the same work or company.

      ## Save, then add images

      Write a short summary of what you're adding, including a source where useful, and create the entry. Covers and screenshots are added from the edit page after the VN exists. See [the image guide](/help/images).

      To add a character to its cast, open that character's editor and use Visual novel appearances. The [character guide](/help/characters) explains the roles and spoiler settings.
      """
    },
    "help/characters" => %{
      title: "Adding characters",
      page_title: "Adding characters • Kaguya",
      description: "How to add a character and link their visual novel appearances.",
      body: """
      Search for the character first. They may already have a page from another work in the same series. If they do, add the missing appearance to that page.

      Otherwise, open [Add character](/contribute/character). Use the character's established name and keep the description useful to someone who hasn't read the VN yet. Avoid revealing a hidden identity or a major plot twist.

      ## Link their visual novels

      In Visual novel appearances, search for a VN and press Add next to the right result. You can link more than one VN. If the VN itself is missing, create that entry first.

      Choose the role for each appearance:

      - **Main:** a protagonist or central viewpoint character.
      - **Primary:** a major member of the cast, such as a main heroine.
      - **Side:** a supporting character.
      - **Appears:** a brief appearance or cameo.

      The same character can have a different role in each work. Choose based on that appearance, not how much you personally like them.

      ## Appearance spoilers

      Ask whether knowing this character appears in the VN would spoil something. Use No spoilers for an ordinary cast member, Minor spoilers for a smaller reveal, and Major spoilers when their presence gives away a significant twist.

      This setting belongs to the appearance. It doesn't make an openly written spoiler in the character's description safe.

      ## Saving changes

      The links, roles and spoiler levels are saved when you save the character. Remove takes a VN out of the form; save the character to apply that removal. It doesn't delete the VN.

      Add a summary explaining what changed. The character editor currently has no image uploader. If the image needs attention, include the character page in a [feedback post](/discussions/feedback).
      """
    },
    "help/producers" => %{
      title: "Adding producers",
      page_title: "Adding producers • Kaguya",
      description: "How to add a company or group behind a visual novel.",
      body: """
      A producer entry represents a company or group involved in making or publishing VNs. Search for its name and any older names before [adding a producer](/contribute/developer).

      ## Name and details

      Use the name the company or group uses publicly. Select the type and language when you know them. Leave uncertain information unset rather than guessing.

      Keep the description factual: who they are, what they make, and any useful context about their history. Credit the source if you use someone else's description.

      ## Developer or publisher?

      A developer makes the work. A publisher releases it. One company can do both, and a translated edition can have a different publisher from the original.

      Creating a producer page doesn't link it to a VN automatically. Open the VN editor, go to Releases and producers, and add them to the relevant release as Developer, Publisher, or both. If there are no releases yet, add the first one there.

      When creating a VN, you can select its developer in the same form. Its initial release is saved with it. For an ongoing VN, update the existing release as new versions arrive; you don't need a separate entry for every version. Use another release for a distinct edition, such as a translation or platform release.

      ## Official links

      Add the group's official website and accounts. Check that each link belongs to this producer, especially when the name is shared by other companies.

      Finish with a short summary of what you added or corrected. If two pages appear to represent the same group, [report the duplicate](/discussions/feedback) with both links rather than changing one into a different producer.
      """
    },
    "help/editing" => %{
      title: "Editing and sources",
      page_title: "Editing and sources • Kaguya",
      description: "Making useful edits, explaining changes and checking revision history.",
      body: """
      Small corrections count. Fixing a broken link or adding a missing title makes the next person's visit better. You don't need to rewrite an entire entry to contribute.

      ## Check your source

      Prefer the work itself, its credits, or an official developer or publisher page. If sources disagree, explain which one you used and why. Leave unknown information blank where the form allows it.

      Descriptions should introduce the work or character. Keep personal ratings and recommendations in reviews. If you quote a description, credit its source and only use text you have permission to reuse. [Formatting help](/formatting-help) explains links and other supported formatting.

      ## Write a useful summary

      Tell the next editor what changed. "Added the official English title from the publisher page" is more useful than "fixed stuff". Include the source URL when it helps someone verify your edit.

      ## History and conflicting edits

      Entry history records revisions so you can see what changed. Check it before undoing another person's work; their summary may explain something you missed.

      If the editor says someone changed the entry while you were working, keep a copy of your unsaved text, reload, and compare the latest version before submitting again.

      If you disagree with an edit, explain the issue and bring a source. Repeatedly undoing each other won't resolve it. Ask in [Feedback](/discussions/feedback) when you need another pair of eyes.

      ## Removed or locked entries

      Don't recreate a removed entry under another name or without its VNDB ID. If you think a decision was wrong, contact the moderators through [Discord](https://discord.gg/stcK4A23jt) and include the details. The same applies when an entry is locked and you can't edit it.
      """
    },
    "help/images" => %{
      title: "Images and content",
      page_title: "Images and content • Kaguya",
      description:
        "Adding covers and screenshots, marking sensitive images and reporting content.",
      body: """
      A good cover helps people recognize a VN. Screenshots help them see what reading it actually looks like. Use images from the work or its official materials that you're allowed to share.

      ## Covers and screenshots

      Create the VN first, then open its edit page to add images. The uploader accepts JPG, JPEG, PNG and WebP files up to 10 MB each.

      Use a cover that clearly identifies the work. For screenshots, capture the game itself at a readable size. Avoid unrelated desktop windows, added watermarks and images that give away major story reveals.

      ## Sensitive images

      Set the available sensitive-content flags accurately. A tame cover doesn't make an explicit screenshot tame, and an adult VN doesn't mean every image is explicit. Judge each image on what it shows.

      Blur preferences let readers control what they see. They don't make prohibited content acceptable to upload. The [Content Policy](/content-policy) applies to entries and their media.

      ## Something shouldn't be here

      Contact the moderators through [Discord](https://discord.gg/stcK4A23jt) or [email](mailto:support@kaguya.io). Include the entry URL and explain the concern in words. Don't repost or attach suspected prohibited material to make the report.

      For an ordinary mistake, such as the wrong cover or a duplicate page, you can also use [Feedback](/discussions/feedback). Include the affected page so we can find it.
      """
    },
    "about" => %{
      title: "About",
      page_title: "About • Kaguya",
      description: "What Kaguya is and why it's called that.",
      body: """
      Kaguya is an all-in-one platform to track, discuss, and discover visual novels. Here's why I built it.

      I've been reading visual novels since 2021, and they have become my favorite medium even beyond books, which I lived on all my childhood. *Fata morgana* I've read 3 whole times. Some of my favorite AVNs I've read more than 5 times.

      I love the intimacy you build with characters over dozens of hours, the right music at the right moment, beautiful artwork and the depth of written storytelling.

      I believe VNs are extremely underrated and more people need to discover them. There's this inexplicable desire in me to help others discover VNs because I enjoy them a lot and I want more people to find them too. Also, an ulterior reason is that more people getting in means more works and we would get more quality stuff to read. ￣▽￣

      Along the way, I've thought more about it and I decided the best thing to build is basically an all-in-one VN platform. One central hub + database + discovery place for visual novels.

      Somewhere to track socially what you're reading, discuss what you've read, write personal reviews, follow friends, build themed lists, customize your profile, see reading history stats, and discover what to read next. All in one place.

      Kaguya is that.

      ## How it started

      Back in April 2024, I had just got out of a rough internship and wanted to work on something meaningful instead of another desk job. I landed on a grandiose vision of building the social discovery app for all entertainment mediums (books, movies, games, tv, and visual novels), with the idea that every story needed to find the people it was meant for.

      At that time, people were most loud about the deplorable state of Goodreads, so I thought why not start with the easiest entry point and then expand from there.

      So, I started building Kaguya, spent over 1.5 years on it, learning everything from SQL to UI design along the way. After all the major features were finally built in Nov 25, I tried building an audience for it, making content and videos, but I kept gravitating toward visual novel stuff instead. Making videos about Fata Morgana when I was supposed to be building a book audience. Visual novels are what I actually read nowadays, so the whole book thing was kind of me larping as something I wasn't anymore.

      Eventually I just tried launching it for VNs to see if anyone would even care. That was January 1, 2026. It got enough attention to know this was the right direction. Closed the book site on February 5 and went VN-only. Since then it's been growing steadily. As of June 2026, Kaguya has over 2,500 registered members.

      ## Why is it called Kaguya?

      It's named after [Princess Kaguya](https://en.wikipedia.org/wiki/The_Tale_of_the_Bamboo_Cutter) from *The Tale of the Bamboo Cutter*. One of the oldest and most foundational Japanese stories. I found the name beautiful and it felt right for what I wanted this to be.
      """
    },
    "development" => %{
      title: "Development",
      page_title: "Development • Kaguya",
      description: "The tech stack behind Kaguya.",
      body: """
      ## The Source

      Kaguya is open source. The full source code of the site is available as a [git repository](https://github.com/KaguyaHQ/kaguya). You can use it to track changes to the code, run your own instance of Kaguya, and contribute to issues or pull requests. Check the README in the repository for instructions. The code is licensed under [AGPL-3.0](https://github.com/KaguyaHQ/kaguya/blob/main/LICENSE).

      ## Tech Stack

      The whole site runs on [Elixir](https://elixir-lang.org/) and [Phoenix](https://www.phoenixframework.org/), with [Phoenix LiveView](https://www.phoenixframework.org/) rendering every page server-side over a live connection, so there's no separate frontend app.

      - [Elixir](https://elixir-lang.org/) & [Phoenix](https://www.phoenixframework.org/) for the application and web layer
      - [Phoenix LiveView](https://www.phoenixframework.org/) for server-rendered UI (HEEx templates)
      - [PostgreSQL](https://www.postgresql.org/) on [Supabase](https://supabase.com/), via [Ecto](https://hexdocs.pm/ecto/)
      - [Oban](https://hexdocs.pm/oban/) for background jobs and scheduled maintenance
      - [Cachex](https://hexdocs.pm/cachex/) for in-memory caching on hot paths
      - [Meilisearch](https://www.meilisearch.com/) for full-text search
      - [Nx](https://hexdocs.pm/nx/) for recommendation inference
      - [Cloudflare R2](https://www.cloudflare.com/developer-platform/r2/) for image and asset storage
      - [Tailwind CSS](https://tailwindcss.com/) & [SaladUI](https://salad-ui.fly.dev/) for styling and components
      """
    },
    "faq" => %{
      title: "FAQ",
      page_title: "FAQ • Kaguya",
      description: "Frequently asked questions about Kaguya.",
      body: """
      ## Is Kaguya free?

      Yes.

      ## Can I import my VNDB list?

      Yes. You can import your VNDB list during onboarding or anytime from your library.

      ## Do I need an account?

      You can browse without an account. Tracking, reviews, lists, and following require one.

      ## How do I delete my account?

      Settings > Account > Delete Account. Deletion is immediate and permanent.

      ## I found a bug or have a suggestion.

      Post it in [Feedback](/discussions/feedback) — bug reports and ideas both welcome.
      """
    },
    "community-guidelines" => %{
      title: "Community Guidelines",
      page_title: "Community Guidelines • Kaguya",
      description: "How we keep Kaguya a good place for visual novel readers.",
      body: """
      Kaguya is a space for visual novel lovers. Keep it respectful and enjoyable for everyone.

      ## 1. Be Respectful

      No harassment, personal attacks, hate speech, or discrimination. Disagree with ideas, without attacking people.

      ## 2. Mark Spoilers

      Clearly warn others before posting spoilers. Use `||spoiler text||` to hide text, or toggle "Contains spoilers" when writing a review.

      ## 3. No Spam

      No low-value posts or excessive self-promotion.

      ## 4. Keep It Legal

      No piracy. Only post content you have the right to share.

      ## 5. Respect Privacy

      Don't share anyone's personal information without consent.

      ## 6. Enforcement

      Violations can result in warnings, suspensions, or bans.
      """
    },
    "review-guidelines" => %{
      title: "Review Guidelines",
      page_title: "Review Guidelines • Kaguya",
      description: "What the review section is for and what's permitted.",
      body: """
      Reviews on Kaguya exist to share your experience with a work and help others decide what to read.

      Reviews should engage with the work. Reviews that are entirely directed at a creator's character or personal attributes, or that attack other users for their taste, may be hidden or removed. Slurs are not permitted. AI-generated reviews will be removed. Reviews should be your own words. Reviews hidden for policy violations can be reposted with the offending content removed.
      """
    },
    "content-policy" => %{
      title: "Content Policy",
      page_title: "Content Policy • Kaguya",
      description: "What belongs on Kaguya and what doesn't",
      body: """
      Visual novels have always included adult content. Kaguya aims to catalogue all of them, including ones with extreme/sensitive content like gore, ero, prejudice, abuse.

      Gameplay hybrids are included in the same catalog as other visual novels.

      The one exception: works that exist solely to sexualize minors (loli/shota nukige).

      Kaguya is a social site for visual novel readers first, and the database exists to serve that purpose rather than to catalog everything for the sake of completeness.

      Everything else belongs on Kaguya.
      """
    },
    "formatting-help" => %{
      title: "Formatting Help",
      page_title: "Formatting Help • Kaguya",
      description: "How to format text in reviews, comments, and bios on Kaguya.",
      body: """
      Reviews, comments, and bios support markdown formatting.

      ## Text

      - **Bold** — `**text**` or Cmd+B
      - *Italic* — `*text*` or Cmd+I
      - ~~Strikethrough~~ — `~~text~~`

      ## Links

      `[display text](url)` or Cmd+K

      ## Spoilers

      Wrap text in double pipes: `||spoiler text||`

      Spoilers appear blurred until the reader clicks them. Use this for plot details, not for the entire review - mark the review itself as a spoiler if the whole thing gives things away.

      ## Lists

      Unordered lists use `-` or `*` at the start of a line. Ordered lists use `1.`, `2.`, etc.

      ## Blockquotes

      Start a line with `>` to quote text.

      ## Code

      Wrap text in single backticks for inline code. Use triple backticks for code blocks.

      ## Line breaks

      A single newline creates a line break. You don't need to add two spaces or a blank line.

      ## What's not supported

      Headings, images, and tables are stripped in reviews and comments. They render in bios.
      """
    },
    "privacy-policy" => %{
      title: "Privacy Policy",
      page_title: "Privacy Policy • Kaguya",
      description:
        "How Kaguya handles your data, what we collect, and how to delete your account.",
      body: """
      ## What we collect

      When you register, you provide a name and email. We use this to run your account.

      ## Analytics

      We use Plausible Analytics, which doesn't use cookies or collect personal data. We also collect basic log data (IP address, browser type, pages visited) for security.

      ## Sharing

      We don't share your data with third parties except when required by law or to enforce our [Terms](#{@base_url}/terms).

      ## Storage

      Your data is stored in Germany.

      ## Deletion

      Settings > Account > Delete Account. This is permanent. We don't keep backups.
      """
    },
    "terms" => %{
      title: "Terms and Conditions",
      page_title: "Terms and Conditions • Kaguya",
      description: "Terms and conditions for using Kaguya.",
      body: """
      ## Age requirement

      You must be at least 18 years old to use Kaguya.

      ## Your account

      You're responsible for keeping your login credentials secure and for any activity on your account.

      ## Conduct

      Don't harass, spam, impersonate others, or do anything illegal. Full details are in our [Community Guidelines](#{@base_url}/community-guidelines).

      ## Your content

      You own what you post. By posting, you give us permission to display it on Kaguya. Don't post content that infringes someone else's rights.

      ## Enforcement

      We can remove content and suspend or terminate accounts that violate these terms. If you think we made a mistake, reach out on our [Discord](https://discord.gg/stcK4A23jt).

      ## Privacy

      We handle your data as described in our [Privacy Policy](#{@base_url}/privacy-policy).
      """
    }
  }

  @doc "Returns `{:ok, page}` for a known slug or `:error`."
  def fetch(slug) when is_binary(slug) do
    case Map.fetch(@pages, slug) do
      {:ok, page} -> {:ok, page}
      :error -> :error
    end
  end

  @doc "List of all routable slugs (for router pattern matching)."
  def slugs, do: Map.keys(@pages)
end
