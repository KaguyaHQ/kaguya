defmodule KaguyaWeb.Policies.Content do
  @moduledoc """
  Static content for the policy / about / FAQ pages.

  Keep this in sync when policy text changes.
  """

  @base_url "https://kaguya.io"

  @pages %{
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
