import {lvNavigate} from "../lib/lv_navigate"

const BrowseAutoApplyFilter = {
  mounted() {
    this.popover = this.el.closest("[data-component='popover']")
    this.wasOpen = false
    this.snapshot = this._signature()

    this._observer = new MutationObserver(() => this._handleStateChange())
    if (this.popover) {
      this._observer.observe(this.popover, {attributes: true, attributeFilter: ["data-state"]})
    }

    this._onSubmit = event => {
      event.preventDefault()
      this._navigate()
    }
    this.el.addEventListener("submit", this._onSubmit)
  },

  destroyed() {
    this._observer?.disconnect()
    this.el.removeEventListener("submit", this._onSubmit)
  },

  _handleStateChange() {
    const open = this.popover?.dataset.state === "open"

    if (open) {
      this.wasOpen = true
      this.snapshot = this._signature()
      return
    }

    if (!this.wasOpen) return
    this.wasOpen = false

    requestAnimationFrame(() => {
      if (this.snapshot !== this._signature()) this._navigate()
    })
  },

  _signature() {
    return Array.from(new FormData(this.el).entries())
      .filter(([, value]) => String(value || "") !== "")
      .map(([key, value]) => `${key}=${value}`)
      .sort()
      .join("&")
  },

  _navigate() {
    const params = new URLSearchParams()
    for (const [key, value] of new FormData(this.el).entries()) {
      const text = String(value || "").trim()
      if (text !== "") params.append(key, text)
    }

    const query = params.toString()
    const action = this.el.getAttribute("action") || window.location.pathname
    // Same LiveView (/browse stays in BrowseLive.Index across action/param
    // changes) — patch keeps state, no remount.
    lvNavigate(query ? `${action}?${query}` : action, "patch")
  },
}

export default BrowseAutoApplyFilter
