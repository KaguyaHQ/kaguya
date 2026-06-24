// Trigger a LiveView client-side navigation from arbitrary JS — equivalent
// to clicking a `<.link navigate>` / `<.link patch>` rendered by HEEx.
//
// Use this instead of `window.location.assign(...)` whenever the destination
// is an in-app LiveView route. A plain `location.assign` causes a full
// browser reload, which kills the topbar progress feel and re-downloads
// CSS/JS for nothing.
//
// `kind` is "redirect" (live_redirect — different LiveView) or "patch"
// (live_patch — same LiveView module, just URL/param change).

export function lvNavigate(href, kind = "redirect") {
  const link = document.createElement("a")
  link.href = href
  link.setAttribute("data-phx-link", kind)
  link.setAttribute("data-phx-link-state", "push")
  // Marks this anchor as a programmatic-navigation shim. Retained so any
  // click-outside handler that wants to ignore synthetic navigation clicks
  // can key off it; the native Popover API light-dismiss no longer needs it.
  link.setAttribute("data-lv-navigate", "true")
  link.style.display = "none"
  document.body.appendChild(link)
  link.click()
  link.remove()
}
