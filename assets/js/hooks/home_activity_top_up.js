// Bounded-feed top-up behaviour:
//
// The sidebar pulls a single bounded page (20 entries) on mount, but
// same-user compaction can render that page visually tiny — leaving a
// large empty gap above the footer. When the rendered feed is shorter
// than the available viewport height, ask the server for one more page
// so the rail fills the rail.
//
// `data-can-top-up` is the server's authoritative flag: it goes false
// once we've topped up the configured number of times (or there are no
// more entries to fetch), and the hook becomes a no-op.

const VIEWPORT_BOTTOM_GAP = 24

const HomeActivityTopUp = {
  mounted() {
    this.maybeTopUp()
  },

  updated() {
    this.maybeTopUp()
  },

  maybeTopUp() {
    if (this.el.dataset.canTopUp !== "true") return
    if (this.scheduled) return
    this.scheduled = true

    window.requestAnimationFrame(() => {
      this.scheduled = false
      if (!this.el.isConnected) return
      if (this.el.getClientRects().length === 0) return

      const top = this.el.getBoundingClientRect().top
      const targetHeight = window.innerHeight - top - VIEWPORT_BOTTOM_GAP
      if (targetHeight <= 0) return

      if (this.el.scrollHeight < targetHeight) {
        this.pushEvent("bounded_top_up", {})
      }
    })
  }
}

export default HomeActivityTopUp
