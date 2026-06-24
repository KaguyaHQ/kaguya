const FadeReadPreference = {
  mounted() {
    this.storageKey = this.el.dataset.storageKey || "fadeReadLists"
    this._syncFromStorage()
    this._persistCurrent()
  },

  updated() {
    this._persistCurrent()
  },

  _isLoggedIn() {
    return this.el.dataset.isLoggedIn === "true"
  },

  _currentValue() {
    return this.el.dataset.fadeRead === "true"
  },

  _syncFromStorage() {
    if (!this._isLoggedIn()) return

    try {
      const stored = localStorage.getItem(this.storageKey)
      if (stored === null) return

      const saved = stored === "true"
      if (saved !== this._currentValue()) {
        this.pushEvent("set_fade_read", {fade_read: saved})
      }
    } catch (_error) {
    }
  },

  _persistCurrent() {
    if (!this._isLoggedIn()) return

    try {
      localStorage.setItem(this.storageKey, String(this._currentValue()))
    } catch (_error) {
    }
  }
}

export default FadeReadPreference
