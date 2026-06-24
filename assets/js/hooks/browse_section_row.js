const BrowseSectionRow = {
  mounted() {
    this._bind()
  },

  updated() {
    this._bind()
  },

  destroyed() {
    this._teardown?.()
  },

  _bind() {
    this._teardown?.()

    this.scroller = this.el.querySelector("[data-browse-section-scroller]")
    this.prevButton = this.el.querySelector("[data-browse-section-arrow='prev']")
    this.nextButton = this.el.querySelector("[data-browse-section-arrow='next']")

    if (!this.scroller || !this.prevButton || !this.nextButton) return

    this._update = () => {
      const maxScroll = Math.max(0, this.scroller.scrollWidth - this.scroller.clientWidth)
      this.prevButton.disabled = this.scroller.scrollLeft <= 1
      this.nextButton.disabled = this.scroller.scrollLeft >= maxScroll - 1
    }

    this._onClick = event => {
      const button = event.target.closest("[data-browse-section-arrow]")
      if (!button || button.disabled) return

      event.preventDefault()
      const direction = button.dataset.browseSectionArrow === "next" ? 1 : -1
      const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches
      const start = this.scroller.scrollLeft
      const maxScroll = Math.max(0, this.scroller.scrollWidth - this.scroller.clientWidth)
      const target = Math.max(0, Math.min(maxScroll, start + direction * this.scroller.clientWidth))

      this.scroller.scrollTo({
        left: target,
        behavior: reduceMotion ? "auto" : "smooth"
      })

      if (!reduceMotion) {
        window.setTimeout(() => {
          if (Math.abs(this.scroller.scrollLeft - start) < 2) {
            this.scroller.scrollTo({left: target, behavior: "auto"})
          }
        }, 120)
      }
    }

    this.scroller.addEventListener("scroll", this._update, {passive: true})
    this.el.addEventListener("click", this._onClick)
    window.addEventListener("resize", this._update, {passive: true})

    if (typeof ResizeObserver !== "undefined") {
      this._resizeObserver = new ResizeObserver(this._update)
      this._resizeObserver.observe(this.scroller)
    }

    requestAnimationFrame(this._update)

    this._teardown = () => {
      this.scroller?.removeEventListener("scroll", this._update)
      this.el.removeEventListener("click", this._onClick)
      window.removeEventListener("resize", this._update)
      this._resizeObserver?.disconnect()
      this._resizeObserver = null
    }
  }
}

export default BrowseSectionRow
