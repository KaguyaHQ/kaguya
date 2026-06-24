import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/kaguya"
import topbar from "topbar"

import Hooks from "./hooks"
import {applyHomeGreeting} from "./hooks/home_greeting"
import {bootstrapStaticNotFound} from "./hooks/not_found_button"
import "./events"
import "./sentry"
import "./web_vitals"

bootstrapStaticNotFound()

// Fill the home greeting immediately on load. app.js is deferred, so the DOM
// is already parsed here — this runs without waiting for the LiveView socket
// to connect. The HomeGreeting hook re-applies it after client navigation.
applyHomeGreeting()

const createSafeStorage = name => {
  let storage

  try {
    storage = window[name]
  } catch (_error) {
    storage = null
  }

  return {
    getItem(key) {
      try {
        return storage?.getItem(key) ?? null
      } catch (_error) {
        return null
      }
    },
    setItem(key, value) {
      try {
        storage?.setItem(key, value)
      } catch (_error) {}
    },
    removeItem(key) {
      try {
        storage?.removeItem(key)
      } catch (_error) {}
    },
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content")
const safeLocalStorage = createSafeStorage("localStorage")
const liveSocket = new LiveSocket("/live", Socket, {
  // Functioned so the values are read at connect time, not module-eval time —
  // lets the server seed client-only UI prefs (e.g. release filters) on mount
  // instead of round-tripping a correction event after first render.
  params: () => ({
    _csrf_token: csrfToken,
    release_filter_prefs: safeLocalStorage.getItem("release-filter-prefs"),
  }),
  localStorage: safeLocalStorage,
  sessionStorage: createSafeStorage("sessionStorage"),
  // Phoenix 1.8 colocated hooks (auto-bundled from <script :type="phx-hook">
  // blocks in HEEx) merged with manually-defined Hooks. Manual hooks win
  // on name conflicts.
  hooks: {...colocatedHooks, ...Hooks},
})

// Topbar progress indicator — only fires for user-initiated navigation
// (clicking a <.link navigate> or <.link patch>, push_navigate/push_patch
// from the server). Filtered to skip:
//   - "initial": WS connect on a hard refresh / first load (page is already
//     visible — showing a bar here is wrong).
//   - "element": phx-click events (use local button loading states, not a
//     global page bar).
//   - "error": reconnect noise.
// 120ms delay on top of that, so fast in-app navs don't flash a bar.
const brandRgb = getComputedStyle(document.documentElement)
  .getPropertyValue("--button-background-brand-default")
  .trim()
const brandColor = brandRgb ? `rgb(${brandRgb})` : "#9b013d"
topbar.config({barColors: {0: brandColor}, shadowColor: "rgba(0, 0, 0, .3)"})

const TOPBAR_KINDS = new Set(["redirect", "patch"])
let topbarScheduled
window.addEventListener("phx:page-loading-start", ({detail: {kind}}) => {
  if (!TOPBAR_KINDS.has(kind)) return
  if (!topbarScheduled) topbarScheduled = setTimeout(() => topbar.show(), 120)
})
window.addEventListener("phx:page-loading-stop", ({detail: {kind}}) => {
  if (!TOPBAR_KINDS.has(kind)) return
  clearTimeout(topbarScheduled)
  topbarScheduled = undefined
  topbar.hide()
})

window.addEventListener("phx:navigate", () => {
  const nav = document.getElementById("mobile-nav")
  if (!nav) return
  nav.setAttribute("data-search", "closed")
  nav.setAttribute("data-state", "closed")
})

liveSocket.connect()
window.liveSocket = liveSocket

// LiveReloader QoL — only fires in dev (Phoenix.LiveReloader is only
// plugged when code_reloading?). Streams server logs to the browser
// console and enables click-to-open-in-editor for HEEx components:
//   * hold "c" + click → opens at caller (the HEEx render site)
//   * hold "d" + click → opens at function-component definition
window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
  reloader.enableServerLogs()

  let keyDown
  window.addEventListener("keydown", e => keyDown = e.key)
  window.addEventListener("keyup", _e => keyDown = null)
  window.addEventListener("click", e => {
    if (keyDown === "c") {
      e.preventDefault()
      e.stopImmediatePropagation()
      reloader.openEditorAtCaller(e.target)
    } else if (keyDown === "d") {
      e.preventDefault()
      e.stopImmediatePropagation()
      reloader.openEditorAtDef(e.target)
    }
  }, true)

  window.liveReloader = reloader
})
