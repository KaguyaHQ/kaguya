const SimilarVnMobileReveal = {
  mounted() {
    this.active = false
    this.media = window.matchMedia("(max-width: 1023.98px)")
    this.controls = this.el.querySelector("[data-similar-vote-controls]")
    this.link = this.el.querySelector("[data-similar-link]")

    this.onItemClick = event => {
      if (!this.isMobile()) return
      if (event.target.closest("[data-vote-control='true']")) return
      if (!this.link?.contains(event.target)) return

      if (!this.active) {
        event.preventDefault()
        event.stopImmediatePropagation()
        this.activate()
      }
    }

    this.onDocumentClick = event => {
      if (!this.active || !this.isMobile()) return
      if (this.el.contains(event.target)) return
      this.deactivate()
    }

    this.onMediaChange = () => {
      this.active = false
      this.sync()
    }

    this.el.addEventListener("click", this.onItemClick, true)
    document.addEventListener("click", this.onDocumentClick, true)

    if (this.media.addEventListener) {
      this.media.addEventListener("change", this.onMediaChange)
    } else {
      this.media.addListener(this.onMediaChange)
    }

    this.sync()
  },

  updated() {
    this.controls = this.el.querySelector("[data-similar-vote-controls]")
    this.link = this.el.querySelector("[data-similar-link]")
    this.sync()
  },

  destroyed() {
    this.el.removeEventListener("click", this.onItemClick, true)
    document.removeEventListener("click", this.onDocumentClick, true)

    if (this.media?.removeEventListener) {
      this.media.removeEventListener("change", this.onMediaChange)
    } else if (this.media?.removeListener) {
      this.media.removeListener(this.onMediaChange)
    }
  },

  isMobile() {
    return this.media.matches
  },

  activate() {
    this.active = true
    this.sync()
  },

  deactivate() {
    this.active = false
    this.sync()
  },

  sync() {
    this.el.dataset.mobileActive = this.active ? "true" : "false"

    if (!this.controls) return

    if (this.isMobile() && !this.active) {
      this.controls.hidden = true
    } else {
      this.controls.hidden = false
    }
  }
}

export default SimilarVnMobileReveal
