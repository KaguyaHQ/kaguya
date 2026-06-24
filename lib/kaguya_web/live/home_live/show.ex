defmodule KaguyaWeb.HomeLive.Show do
  @moduledoc """
  Home page LiveView (`/`).

  Mirrors the Next.js landing page at
  `../personal/legacy-next-app/src/components/landing/LandingPage.tsx`:

    * Cinematic hero with a 1125-wide centered backdrop, gradient fades
      on the sides/top/bottom, and a vertical Letterboxd-style VN-title
      link on the right edge (xl breakpoint and up).
    * Static curated 4/6-cover row (mobile shows 4, sm+ shows 6).
    * Four product-showcase sections alternating direction.

  The hero overlays the navbar (`nav_transparent: true`), exactly like
  prod where the `LandingPage` root has `lg:-mt-[72px]` to pull itself
  under a transparent navbar.

  The logged-in-only `VNHomePage` (greeting + activity/feed tabs) is a
  separate surface that depends on infinite-feed plumbing and isn't
  ported yet. For now both anonymous and authenticated visitors get the
  landing page; sign-in still works via the navbar.
  """

  use KaguyaWeb, :live_view

  alias KaguyaWeb.HomeLive.Landing

  @impl true
  def mount(_params, _session, socket) do
    {:ok, Landing.assign_landing(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <script type="application/ld+json">
      <%= raw(json_ld()) %>
    </script>

    <link rel="preload" href={Landing.hero_image_url()} as="image" type="image/webp" />

    <Landing.landing_page
      hero_image={@hero_image}
      covers={@covers}
      stats={@stats}
      showcases={@showcases}
    />
    """
  end

  defp json_ld do
    Jason.encode!(%{
      "@context" => "https://schema.org",
      "@type" => "WebSite",
      "url" => "https://kaguya.io/",
      "name" => "Kaguya",
      "alternateName" => "kaguya.io"
    })
  end
end
