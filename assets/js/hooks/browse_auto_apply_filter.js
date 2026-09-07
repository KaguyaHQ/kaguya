import {lvNavigate} from "../lib/lv_navigate"

const BrowseAutoApplyFilter = {
  mounted() {
    this.popover = this.el.closest("[popover]")
    this.snapshot = this._signature()

    this._onBeforeToggle = event => {
      if (event.newState === "open") this.snapshot = this._signature()
    }
    this._onToggle = event => {
      if (event.newState !== "closed") return
      // Wait for focused number inputs to commit/clamp their values on blur.
      this._cancelPending()
      this.pendingApply = requestAnimationFrame(() => this._applyChanges())
    }
    this._onSubmit = event => {
      event.preventDefault()
      if (this.el.contains(document.activeElement)) document.activeElement.blur()
      this._applyChanges()
      if (this.popover?.matches(":popover-open")) this.popover.hidePopover()
    }
    this._onKeydown = event => {
      if (event.key === "Enter" && !event.isComposing && event.target.matches("input:not([type=range])")) {
        event.preventDefault()
        this.el.requestSubmit()
      }
    }
    // An explicit navigation (e.g. Clear) takes precedence over a pending
    // light-dismiss apply, so the old draft cannot overwrite the new URL.
    this._onNavigation = () => this._cancelPending()

    this.popover?.addEventListener("beforetoggle", this._onBeforeToggle)
    this.popover?.addEventListener("toggle", this._onToggle)
    this.el.addEventListener("submit", this._onSubmit)
    this.el.addEventListener("keydown", this._onKeydown)
    window.addEventListener("phx:page-loading-start", this._onNavigation)
  },

  updated() {
    if (!this.popover?.matches(":popover-open")) this.snapshot = this._signature()
  },

  destroyed() {
    this._cancelPending()
    this.popover?.removeEventListener("beforetoggle", this._onBeforeToggle)
    this.popover?.removeEventListener("toggle", this._onToggle)
    this.el.removeEventListener("submit", this._onSubmit)
    this.el.removeEventListener("keydown", this._onKeydown)
    window.removeEventListener("phx:page-loading-start", this._onNavigation)
  },

  _cancelPending() {
    cancelAnimationFrame(this.pendingApply)
    this.pendingApply = null
  },

  _applyChanges() {
    this._cancelPending()
    const signature = this._signature()
    if (signature === this.snapshot) return
    this.snapshot = signature
    this._navigate()
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
    lvNavigate(query ? `${action}?${query}` : action, "patch")
  },
}

export default BrowseAutoApplyFilter
