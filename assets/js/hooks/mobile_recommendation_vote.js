/*
 * MobileRecommendationVote — port of SimilarVnItem's mobile gating.
 *
 * On viewports < 1024px the per-recommendation vote arrows (rendered as
 * `.vote-arrow` inside the hooked `[data-vote-control]` element) start
 * hidden via CSS (`opacity: 0; pointer-events: none`). The first tap on
 * the cover sets `data-revealed="true"` to expose them; a tap anywhere
 * outside the item clears it. Desktop (>= 1024px) uses pure-CSS
 * hover/focus reveal — the hook is a no-op there.
 */
const MobileRecommendationVote = {
  mounted() {
    this._isMobile = () => window.innerWidth < 1024
    this._reveal = () => {
      if (!this._isMobile()) return
      this.el.dataset.revealed = "true"
    }
    this._dismiss = () => {
      if (this.el.dataset.revealed === "true") delete this.el.dataset.revealed
    }
    this._onClick = event => {
      if (!this._isMobile()) return
      if (this.el.dataset.revealed === "true") return
      // First tap reveals controls and follows the cover link on the
      // second tap — swallow this tap so the link isn't followed yet.
      const link = event.target.closest("a")
      if (link && this.el.contains(link)) {
        event.preventDefault()
        event.stopPropagation()
      }
      this._reveal()
    }
    this._onDocumentPointerDown = event => {
      if (!this._isMobile()) return
      if (this.el.dataset.revealed !== "true") return
      if (this.el.contains(event.target)) return
      this._dismiss()
    }

    this.el.addEventListener("click", this._onClick)
    document.addEventListener("pointerdown", this._onDocumentPointerDown, true)
  },

  destroyed() {
    this.el.removeEventListener("click", this._onClick)
    document.removeEventListener("pointerdown", this._onDocumentPointerDown, true)
  }
}

export default MobileRecommendationVote
