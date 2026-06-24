// Browser-side Sentry init for the LiveView surface.
//
//   - Manual sampling in `beforeSend` so events tagged critical=true always
//     ship (auth, billing) while everything else is sampled at 25%.
//   - Broad `ignoreErrors` list covering common browser/network/extension noise.
//
// No session/error replay: the replay SDK is ~122kb (the largest chunk of the
// bundle) and records a rolling buffer on every session. We don't review
// replays, so it isn't loaded. Re-add `Sentry.replayIntegration()` (eagerly,
// to keep pre-error context behind the same-origin tunnel) if that changes.
//
// DSN / release / environment are surfaced via <meta name="sentry-*"> tags in
// the root layout — driven server-side by the `:sentry_browser` config block.
// By default `SENTRY_BROWSER_DSN` is unset and falls back to `SENTRY_DSN`, so
// browser and backend events share one Sentry project; they're split in the UI
// by the `source` tag ("liveview" here, set below). Point `SENTRY_BROWSER_DSN`
// at its own project only if you want browser events fully isolated.

import * as Sentry from "@sentry/browser"

const GENERAL_SAMPLE_RATE = 0.25

const meta = name => document.querySelector(`meta[name='${name}']`)?.content || null

const dsn = meta("sentry-dsn")

// Aloha Browser on iOS reports failures from its internal native bridge as
// global NetworkError events. These are not app/API failures.
const eventMessage = event => {
  const exception = event.exception?.values?.[0]
  return [event.message, exception?.type, exception?.value].filter(Boolean).join(" ")
}

const hasAlohaNativeCallBreadcrumb = event =>
  event.breadcrumbs?.some(breadcrumb => breadcrumb.data?.url?.startsWith("aloha-extension://"))

const isAlohaNativeCallNetworkError = event =>
  hasAlohaNativeCallBreadcrumb(event) &&
  /A network error occurred|NetworkError/.test(eventMessage(event))

if (dsn) {
  Sentry.init({
    dsn,
    release: meta("sentry-release"),
    environment: meta("sentry-environment"),

    // Same-origin proxy so adblockers can't filter out the ingest
    // requests. Matches the POST /_sen_tunnel route registered in
    // KaguyaWeb.Router; the controller validates the DSN before forwarding.
    tunnel: "/_sen_tunnel",

    // Sampling is handled manually in beforeSend so critical events always
    // ship at 100% regardless of the general rate.
    sampleRate: 1.0,
    tracesSampleRate: 0,

    initialScope: scope => {
      scope.setTag("source", "liveview")
      return scope
    },

    // Drop known browser noise before event processing.
    ignoreErrors: [
      // Browser quirks
      /Failed to read the 'localStorage' property from 'Window'/,
      /The operation is insecure/,
      /The request was denied/,
      /ResizeObserver loop/,

      // Aborts from navigation / Phoenix LV teardown
      /signal is aborted without reason/,
      /AbortError/,

      // Client network drops (user's connection, not our problem)
      /Failed to fetch/, // Chrome
      /Load failed/, // Safari
      /NetworkError when attempting to fetch resource/, // Firefox

      // Supabase auth lock on slow browsers / multiple tabs
      /Acquiring an exclusive Navigator LockManager lock/,

      // Unsupported AbortSignal APIs on old browsers (iOS <17.4, etc.)
      /AbortSignal\.\w+ is not a function/,

      // Browser extensions (Google Translate, etc.) mutate the DOM and
      // break Phoenix LiveView's morphdom reconciler.
      /Failed to execute 'removeChild' on 'Node'/,
      /Failed to execute 'insertBefore' on 'Node'/,
      /The object can not be found here/, // WebKit version of the above

      // Brave/Firefox for iOS inject content scripts under window.__firefox__
      // (Brave iOS is forked from Firefox iOS) — reader mode, YouTube quality,
      // etc. These throw in page global scope with no app frames in the stack.
      /__firefox__/,
      // Brave Wallet (and other web3 wallets) inject window.ethereum.
      /window\.ethereum/,
      // Dark Reader extension injects a `DarkReader` global.
      /DarkReader/,

      // WebSocket constructor wrapped by a browser extension / proxy tool
      // rejects the URL. Clustered on CF-challenged sessions with zh locale —
      // bot-like clients, 0 real users impacted.
      /Failed to construct 'WebSocket'/,
    ],

    beforeSend(event) {
      if (isAlohaNativeCallNetworkError(event)) return null
      // Critical events always go through at 100%.
      if (event.tags?.critical === "true") return event
      // Sample everything else at the general rate.
      if (Math.random() > GENERAL_SAMPLE_RATE) return null
      return event
    },
  })

  // Phoenix LV surfaces socket errors via `phx:live_socket:error` — capture
  // them as messages so we can correlate disconnects with backend logs.
  window.addEventListener("phx:live_socket:error", e => {
    Sentry.captureMessage("liveview_socket_error", {
      level: "warning",
      extra: { detail: e.detail },
    })
  })
}

export default Sentry
