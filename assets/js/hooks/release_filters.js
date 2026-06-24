// Persists the release language/platform selection to localStorage so it can
// be restored on the next visit. The *restore* happens server-side: the saved
// value is sent through LiveSocket connect params (see app.js) and seeded into
// the LiveView on mount, so the form renders with the right option already
// selected. This hook therefore only writes — it never pushes an event, which
// is what previously caused a mount → reload → remount flash loop.
const ReleaseFilters = {
  mounted() {
    this.storageKey = "release-filter-prefs"
    this.el.addEventListener("change", () => this.savePrefs())
  },
  savePrefs() {
    try {
      const language = this.el.querySelector('[name="release_filters[language]"]')?.value || ""
      const platform = this.el.querySelector('[name="release_filters[platform]"]')?.value || ""
      localStorage.setItem(this.storageKey, JSON.stringify({language, platform}))
    } catch (_error) {
    }
  }
}

export default ReleaseFilters
