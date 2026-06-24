// Pushes a history entry while the mobile search overlay is open so the
// browser back button closes the overlay instead of navigating away.
//
// Unsaved-change prompts live in the `UnsavedChanges` hook.

const MobileSearchHistory = {
  mounted() {
    this._overlayOpen = false
    this._onPopState = () => {
      if (!this._overlayOpen) return

      this._overlayOpen = false
      window.removeEventListener("popstate", this._onPopState)
      this.pushEvent("close_mobile_search", {})
    }
    this._sync()
  },

  updated() {
    this._sync()
  },

  destroyed() {
    window.removeEventListener("popstate", this._onPopState)
  },

  _sync() {
    const nextOpen = this.el.dataset.mobileSearchOpen === "true"

    if (nextOpen && !this._overlayOpen) {
      this._overlayOpen = true
      window.history.pushState({kaguyaMobileSearch: true}, "")
      window.addEventListener("popstate", this._onPopState)
    } else if (!nextOpen && this._overlayOpen) {
      this._overlayOpen = false
      window.removeEventListener("popstate", this._onPopState)
    }
  }
}

export default MobileSearchHistory
