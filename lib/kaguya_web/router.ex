defmodule KaguyaWeb.Router do
  use KaguyaWeb, :router

  pipeline :webhook do
    plug :accepts, ["json"]
    plug KaguyaWeb.Plugs.WebhookRateLimit
  end

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {KaguyaWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug KaguyaWeb.UserAuth, :fetch_current_user
    plug KaguyaWeb.Plugs.ObservabilityContext
  end

  scope "/" do
    get("/health", KaguyaWeb.HealthController, :check)
    get("/dumps.json", KaguyaWeb.DumpsController, :index)
  end

  scope "/", KaguyaWeb do
    get "/sitemap.xml", SitemapController, :index
    get "/sitemap/:id", SitemapController, :show
    get "/data/:hash/vn-tags.json", AssetController, :vn_tags
  end

  scope "/", KaguyaWeb do
    pipe_through :browser

    get "/auth/google", BrowserAuthController, :start_google
    get "/auth/callback", BrowserAuthController, :callback
    get "/auth/confirm", BrowserAuthController, :confirm
    get "/auth/update-email", BrowserAuthController, :update_email_legacy_redirect
    post "/auth/sign-in", BrowserAuthController, :sign_in
    post "/auth/sign-up", BrowserAuthController, :sign_up
    post "/auth/verify-email", BrowserAuthController, :verify_email
    post "/auth/resend-confirmation", BrowserAuthController, :resend_confirmation
    post "/auth/reset-password", BrowserAuthController, :reset_password
    post "/auth/update-recovery-password", BrowserAuthController, :update_recovery_password
    post "/account/update-password", BrowserAuthController, :update_password
    post "/account/update-email", BrowserAuthController, :update_email
    post "/auth/sign-out", BrowserAuthController, :sign_out
    get "/search/visual-novels", SearchController, :visual_novels

    get "/signup", SignupController, :index

    live_session :default,
      on_mount: [{KaguyaWeb.UserAuth, :default}],
      session: {KaguyaWeb.LiveSession, :session, []} do
      live "/login", AuthLive.Login, :index
      live "/", HomeLive.Index, :index
      live "/search", SearchLive.Index, :index
      live "/site-stats", SiteStatsLive.Index, :index
      live "/dumps", DumpsLive.Index, :index
      live "/members", MembersLive.Index, :index
      live "/browse", BrowseLive.Index, :index
      live "/browse/characters", BrowseLive.Index, :characters
      live "/history", ChangesLive.Index, :index
      live "/history/:id", ChangesLive.Show, :show
      live "/character/:slug/history/:revision_id", ChangesLive.Show, :show
      live "/developer/:slug/history/:revision_id", ChangesLive.Show, :show
      live "/series/:slug/history/:revision_id", ChangesLive.Show, :show
      live "/vn/:slug/history/:revision_id", ChangesLive.Show, :show
      live "/vn/:slug/release/:release_id/history/:revision_id", ChangesLive.Show, :show
      live "/discussions", DiscussionLive.Index, :index
      live "/discussions/p/:short_id/:post_slug", DiscussionLive.Show, :show

      live "/discussions/p/:short_id/:post_slug/c/:comment_short_id",
           DiscussionLive.Show,
           :show_comment

      live "/discussions/:category_slug", DiscussionLive.Index, :category
      live "/notifications", NotificationsLive.Index, :index
      live "/moderation/reports", ModerationLive.Reports, :index
      live "/vn-recommender", RecommendationLive.Index, :index
      live "/vn-recommender/:vndb_user_id", RecommendationLive.Index, :index
      live "/lists", ListLive.Index, :index
      live "/list/new", ListLive.Form, :new
      live "/settings", SettingsLive.Index, :index
      live "/settings/integrations", SettingsLive.Index, :integrations
      live "/account/settings", SettingsLive.Index, :index
      live "/account/edit/profile", AccountLive.EditProfile, :index
      live "/account/edit/password", AccountLive.ChangePassword, :index
      live "/account/edit/email", AccountLive.ChangeEmail, :index
      live "/account/import", AccountLive.Import, :index
      live "/account/import/summary", AccountLive.Import, :summary
      live "/account/import/summary/dev", AccountLive.Import, :summary
      live "/@:username/list/:slug", ListLive.Show, :show
      live "/@:username/list/:slug/edit", ListLive.Form, :edit
      live "/@:username/reviews/:vn_slug", ReviewLive.Show, :show
      live "/@:username/discussions/:short_id", DiscussionLive.Show, :user_post
      live "/vn/:slug/edit", VNLive.Edit, :edit
      live "/vn/:slug/similar", VNLive.Similar, :index
      live "/vn/:slug/ratings/:rating", VNLive.Ratings, :index
      live "/vn/:slug/history", VNLive.History, :index
      live "/vn/:slug/discussions/:short_id", DiscussionLive.Show, :vn_post
      live "/vn/:slug/covers", VNLive.Show, :covers
      live "/vn/:slug/screenshots", VNLive.Show, :screenshots
      live "/vn/:slug/quotes", VNLive.Show, :quotes
      live "/vn/:slug", VNLive.Show, :show
      live "/developer/:slug/followers", DeveloperLive.Followers, :index
      live "/developer/:slug/history", DeveloperLive.History, :index
      live "/developer/:slug/edit", DeveloperLive.Edit, :edit
      live "/developer/:slug", DeveloperLive.Show, :show
      live "/developer/:slug/discussions/:short_id", DiscussionLive.Show, :producer_post
      live "/character/:slug/fans", CharacterLive.Fans, :index
      live "/character/:slug", CharacterLive.Show, :show
      live "/character/:slug/discussions/:short_id", DiscussionLive.Show, :character_post
      live "/character/:slug/history", CharacterLive.History, :index
      live "/character/:slug/edit", CharacterLive.Edit, :edit
      live "/series/:slug", SeriesLive.Show, :show

      # Create forms live under /contribute/:type so they can never collide
      # with an entity slug (a VN named "New" owns /vn/new). Add
      # /contribute/series here once that form is ported.
      live "/contribute/vn", VNLive.Edit, :new
      live "/contribute/character", CharacterLive.Edit, :new
      live "/contribute/developer", DeveloperLive.Edit, :new

      live "/about", PoliciesLive.Show, :about
      live "/development", PoliciesLive.Show, :development
      live "/faq", PoliciesLive.Show, :faq
      live "/community-guidelines", PoliciesLive.Show, :community_guidelines
      live "/review-guidelines", PoliciesLive.Show, :review_guidelines
      live "/content-policy", PoliciesLive.Show, :content_policy
      live "/formatting-help", PoliciesLive.Show, :formatting_help
      live "/privacy-policy", PoliciesLive.Show, :privacy_policy
      live "/terms", PoliciesLive.Show, :terms

      # Profile pages. `/@:username` matches the at-sign literally, so the
      # `:username` param arrives without the `@` prefix (same as the
      # existing `/@:username/list/:slug` routes above).
      live "/@:username", ProfileLive.Show, :show
      live "/@:username/activity", ProfileLive.Activity, :show
      live "/@:username/library", ProfileLive.Library, :show
      live "/@:username/library/:shelf", ProfileLive.Library, :show
      live "/@:username/reviews", ProfileLive.Reviews, :show
      live "/@:username/lists", ProfileLive.Lists, :show
      live "/@:username/discussions", ProfileLive.Discussions, :show
      live "/@:username/favorites", ProfileLive.Favorites, :show
      live "/@:username/stats", ProfileLive.Stats, :show
      live "/@:username/recs", ProfileLive.Recs, :show
      live "/@:username/edits", ProfileLive.Edits, :show
      live "/@:username/followers", ProfileLive.Follows, :followers
      live "/@:username/following", ProfileLive.Follows, :following
      live "/@:username/votes/tag", ProfileLive.TagVotes, :show
    end

    if Mix.env() in [:dev, :test] do
      live "/dev/ui/style-guide", Dev.StyleGuideLive, :index
    end
  end

  # Browser observability proxy — sendBeacon target for Web Vitals and
  # similar client-side telemetry. Reuses the existing webhook rate-
  # limit (per-IP, 120/min) so a misbehaving tab can't drown Axiom.
  scope "/api", KaguyaWeb do
    pipe_through :webhook
    post "/axiom", ObservabilityController, :ingest
  end

  # Sentry browser-SDK tunnel — same-origin proxy so adblockers don't
  # filter out the SDK's ingest requests. The controller validates the
  # envelope's embedded DSN against our configured browser DSN to
  # prevent open-relay abuse. Path matches the JS `tunnel:` config in
  # `assets/js/sentry.js`.
  scope "/", KaguyaWeb do
    pipe_through :webhook
    post "/_sen_tunnel", SentryTunnelController, :tunnel
  end

  if Application.compile_env(:kaguya, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser
      live_dashboard "/dashboard"
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  # Catch-all for unmatched browser GETs. Must be last so it doesn't shadow
  # any dedicated route above. Anything that
  # falls through here renders the branded 404 page with HTTP 404.
  scope "/", KaguyaWeb do
    pipe_through :browser
    get "/*path", NotFoundController, :call
  end
end
