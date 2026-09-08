const Gallery = {
  mounted() {
    this._touchStart = null

    this._activateControl = selector => {
      const control = this.el.querySelector(selector)
      if (control instanceof HTMLElement) control.click()
    }

    this._onClick = event => {
      if (!(event.target instanceof Element)) return
      if (event.target.closest("[data-modal-fullscreen]")) {
        this._toggleFullscreen()
      }
    }

    this._onTouchStart = event => {
      if (!(event.target instanceof Element) || !event.target.closest("[data-media-stage]")) {
        this._touchStart = null
        return
      }

      const touch = event.changedTouches[0]
      this._touchStart = touch ? {x: touch.clientX, y: touch.clientY} : null
    }

    this._onTouchEnd = event => {
      if (!this._touchStart) return

      const touch = event.changedTouches[0]
      if (!touch) return

      const deltaX = touch.clientX - this._touchStart.x
      const deltaY = touch.clientY - this._touchStart.y
      this._touchStart = null

      if (Math.abs(deltaX) < 50 || Math.abs(deltaX) <= Math.abs(deltaY)) return

      // Prevent the synthetic mouse click after a handled touch gesture.
      event.preventDefault()
      this._activateControl(deltaX > 0 ? "[data-modal-previous]" : "[data-modal-next]")
    }

    this._onFullscreenChange = () => this._updateFullscreenControl()

    this._onKeyDown = event => {
      if (event.key === "ArrowLeft" && this.el.querySelector("[data-modal-previous]")) {
        event.preventDefault()
        this._activateControl("[data-modal-previous]")
        return
      }

      if (event.key === "ArrowRight" && this.el.querySelector("[data-modal-next]")) {
        event.preventDefault()
        this._activateControl("[data-modal-next]")
        return
      }

    }

    this.el.addEventListener("click", this._onClick)
    this.el.addEventListener("keydown", this._onKeyDown)
    this.el.addEventListener("touchstart", this._onTouchStart, {passive: true})
    this.el.addEventListener("touchend", this._onTouchEnd, {passive: false})
    document.addEventListener("fullscreenchange", this._onFullscreenChange)

    requestAnimationFrame(() => {
      this._scrollActiveThumbnail()
      this._preloadAdjacentMedia()
    })
  },

  updated() {
    this._updateFullscreenControl()
    this._scrollActiveThumbnail()
    this._preloadAdjacentMedia()
  },

  destroyed() {
    this.el.removeEventListener("click", this._onClick)
    this.el.removeEventListener("keydown", this._onKeyDown)
    this.el.removeEventListener("touchstart", this._onTouchStart)
    this.el.removeEventListener("touchend", this._onTouchEnd)
    document.removeEventListener("fullscreenchange", this._onFullscreenChange)

  },

  _toggleFullscreen() {
    if (!document.fullscreenEnabled) return

    if (document.fullscreenElement === this.el) {
      document.exitFullscreen().catch(() => {})
    } else {
      this.el.requestFullscreen().catch(() => {})
    }
  },

  _updateFullscreenControl() {
    const button = this.el.querySelector("[data-modal-fullscreen]")
    if (!(button instanceof HTMLElement)) return

    const fullscreen = document.fullscreenElement === this.el
    button.setAttribute("aria-pressed", String(fullscreen))
    button.setAttribute("aria-label", fullscreen ? "Exit fullscreen" : "Enter fullscreen")
  },

  _scrollActiveThumbnail() {
    const thumbnail = this.el.querySelector("[data-media-thumbnail][data-media-selected='true']")
    if (thumbnail instanceof HTMLElement) {
      thumbnail.scrollIntoView({behavior: "smooth", block: "nearest", inline: "center"})
    }
  },

  _preloadAdjacentMedia() {
    const thumbnails = Array.from(this.el.querySelectorAll("[data-media-thumbnail]"))
    const activeIndex = thumbnails.findIndex(element => element.dataset.mediaSelected === "true")
    if (activeIndex < 0 || thumbnails.length < 2) return

    const indexes = [
      (activeIndex - 1 + thumbnails.length) % thumbnails.length,
      (activeIndex + 1) % thumbnails.length
    ]

    indexes.forEach(index => {
      const src = thumbnails[index]?.dataset.mediaSrc
      if (src) new Image().src = src
    })
  }
}

export default Gallery
