/* Library display preferences belong to the browser, not the viewed profile.
 * Restore only applicable preferences and persist only explicit user changes;
 * an unrelated LiveView patch must never write default assigns over storage.
 */
const LibraryPrefs = {
  mounted() {
    this._syncFromStorage()
    this._onClick = event => {
      if (event.target.closest("[data-fade-toggle]") && this._canFade()) {
        this._fadeValue = !this._fadeValue
        this._setPreference("fadeReadLibrary", "set_fade_read", this._fadeValue)
      } else if (event.target.closest("[data-show-dates-toggle]") && this._isOwner()) {
        this._datesValue = !this._datesValue
        this._setPreference("showDatesLibrary", "set_show_dates", this._datesValue)
      }
    }
    this.el.addEventListener("click", this._onClick)
  },

  updated() {
    if (this._scope !== this._currentScope()) this._syncFromStorage()
  },

  destroyed() {
    this.el.removeEventListener("click", this._onClick)
  },

  _isOwner() { return this.el.dataset.isOwner === "true" },
  _canFade() { return !this._isOwner() && this.el.dataset.isLoggedIn === "true" },
  _currentScope() { return `${this.el.dataset.isOwner}:${this.el.dataset.isLoggedIn}` },

  _read(key, fallback) {
    try {
      const value = localStorage.getItem(key)
      return value === "true" ? true : value === "false" ? false : fallback
    } catch (_error) {
      return fallback
    }
  },

  _setPreference(key, event, value) {
    try { localStorage.setItem(key, String(value)) } catch (_error) {}
    this.pushEvent(event, {value})
  },

  _syncFromStorage() {
    this._scope = this._currentScope()
    this._fadeValue = this._read("fadeReadLibrary", this.el.dataset.fadeRead === "true")
    this._datesValue = this._read("showDatesLibrary", this.el.dataset.showDates === "true")

    if (this._canFade() && this._fadeValue !== (this.el.dataset.fadeRead === "true")) {
      this.pushEvent("set_fade_read", {value: this._fadeValue})
    }
    if (this._isOwner() && this._datesValue !== (this.el.dataset.showDates === "true")) {
      this.pushEvent("set_show_dates", {value: this._datesValue})
    }
  }
}

export default LibraryPrefs
