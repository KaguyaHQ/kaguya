/*
 * LibraryPrefs — bridge between LiveView and localStorage for the
 * library tab's `fadeReadLibrary` and `showDatesLibrary` toggles.
 *
 * On mount, reads localStorage and pushes the current value to LiveView
 * via `set_fade_read` / `set_show_dates`. When the user clicks an in-page
 * toggle button (marked with `data-fade-toggle` or `data-show-dates-toggle`),
 * the hook flips the local value, persists to storage, and pushes the new
 * value to LiveView so the server-rendered assigns mirror the client.
 *
 * Data attributes:
 *   data-fade-read       — current LV value, mirrored back to storage on update.
 *   data-show-dates      — current LV value, mirrored back to storage on update.
 *   data-is-owner        — "true" if the viewer is the profile owner.
 *   data-is-logged-in    — "true" if the viewer is signed in.
 */
const LibraryPrefs = {
  mounted() {
    this._syncFromStorage()
    this._wireToggles()
  },

  updated() {
    // Mirror server state into storage so a back-button refresh stays
    // consistent without round-tripping through the server again.
    this._persistCurrent("fadeReadLibrary", this._fadeRead())
    this._persistCurrent("showDatesLibrary", this._showDates())
    this._unwireToggles()
    this._wireToggles()
  },

  destroyed() {
    this._unwireToggles()
  },

  _fadeRead() { return this.el.dataset.fadeRead === "true" },
  _showDates() { return this.el.dataset.showDates === "true" },
  _isOwner() { return this.el.dataset.isOwner === "true" },
  _isLoggedIn() { return this.el.dataset.isLoggedIn === "true" },

  _read(key) {
    try {
      const value = localStorage.getItem(key)
      return value === null ? null : value === "true"
    } catch (_error) {
      return null
    }
  },

  _persistCurrent(key, value) {
    try { localStorage.setItem(key, String(value)) } catch (_error) {}
  },

  _syncFromStorage() {
    // Fade-read is owner-hidden — only sync for non-owners signed in.
    if (!this._isOwner() && this._isLoggedIn()) {
      const stored = this._read("fadeReadLibrary")
      if (stored !== null && stored !== this._fadeRead()) {
        this.pushEvent("set_fade_read", {value: stored})
      }
    }

    // Show-dates is owner-only.
    if (this._isOwner()) {
      const stored = this._read("showDatesLibrary")
      if (stored !== null && stored !== this._showDates()) {
        this.pushEvent("set_show_dates", {value: stored})
      }
    }
  },

  _wireToggles() {
    this._onFadeClick = () => {
      const next = !this._fadeRead()
      this._persistCurrent("fadeReadLibrary", next)
      this.pushEvent("set_fade_read", {value: next})
    }
    this._onShowDatesClick = () => {
      const next = !this._showDates()
      this._persistCurrent("showDatesLibrary", next)
      this.pushEvent("set_show_dates", {value: next})
    }

    this.el.querySelectorAll("[data-fade-toggle]").forEach(el => {
      el.addEventListener("click", this._onFadeClick)
    })
    this.el.querySelectorAll("[data-show-dates-toggle]").forEach(el => {
      el.addEventListener("click", this._onShowDatesClick)
    })
  },

  _unwireToggles() {
    this.el.querySelectorAll("[data-fade-toggle]").forEach(el => {
      el.removeEventListener("click", this._onFadeClick)
    })
    this.el.querySelectorAll("[data-show-dates-toggle]").forEach(el => {
      el.removeEventListener("click", this._onShowDatesClick)
    })
  }
}

export default LibraryPrefs
