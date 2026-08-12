const ModalDialog = {
  mounted() {
    this.previousActiveElement = document.activeElement instanceof HTMLElement
      ? document.activeElement
      : null
    this._lockBodyScroll()
    this._touchStart = null
    this._swiped = false

    this._focusableElements = () => Array.from(
      this.el.querySelectorAll([
        "a[href]",
        "button:not([disabled])",
        "textarea:not([disabled])",
        "input:not([disabled])",
        "select:not([disabled])",
        "[tabindex]:not([tabindex='-1'])"
      ].join(","))
    ).filter(element => {
      if (!(element instanceof HTMLElement)) return false
      if (element.closest("[hidden]")) return false
      const style = window.getComputedStyle(element)
      return style.display !== "none" && style.visibility !== "hidden"
    })

    this._requestClose = () => {
      const cancel = this.el.querySelector("[data-modal-cancel]")
      if (cancel) {
        cancel.dispatchEvent(new MouseEvent("click", {bubbles: true, cancelable: true}))
      }
    }

    this._activateControl = selector => {
      const control = this.el.querySelector(selector)
      if (control instanceof HTMLElement) control.click()
    }

    this._onMouseDown = event => {
      if (event.target === this.el) this._requestClose()
    }

    this._onClick = event => {
      if (!(event.target instanceof Element)) return
      if (this._swiped) {
        this._swiped = false
        event.preventDefault()
        event.stopPropagation()
        return
      }

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
      this._swiped = false
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

      this._swiped = true
      this._activateControl(deltaX > 0 ? "[data-modal-previous]" : "[data-modal-next]")
    }

    this._onFullscreenChange = () => this._updateFullscreenControl()

    this._onKeyDown = event => {
      if (event.key === "Escape") {
        event.preventDefault()
        this._requestClose()
        return
      }

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

      if (event.key !== "Tab") return

      const focusable = this._focusableElements()
      if (focusable.length === 0) {
        event.preventDefault()
        return
      }

      const first = focusable[0]
      const last = focusable[focusable.length - 1]

      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault()
        last.focus()
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault()
        first.focus()
      }
    }

    this.el.addEventListener("mousedown", this._onMouseDown)
    this.el.addEventListener("click", this._onClick)
    this.el.addEventListener("keydown", this._onKeyDown)
    this.el.addEventListener("touchstart", this._onTouchStart, {passive: true})
    this.el.addEventListener("touchend", this._onTouchEnd, {passive: true})
    document.addEventListener("fullscreenchange", this._onFullscreenChange)

    requestAnimationFrame(() => {
      const initial = this.el.querySelector("[data-modal-initial-focus]")
      const focusTarget = initial || this._focusableElements()[0]
      if (focusTarget instanceof HTMLElement) focusTarget.focus({preventScroll: true})
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
    this.el.removeEventListener("mousedown", this._onMouseDown)
    this.el.removeEventListener("click", this._onClick)
    this.el.removeEventListener("keydown", this._onKeyDown)
    this.el.removeEventListener("touchstart", this._onTouchStart)
    this.el.removeEventListener("touchend", this._onTouchEnd)
    document.removeEventListener("fullscreenchange", this._onFullscreenChange)
    this._unlockBodyScroll()

    if (this.previousActiveElement && document.contains(this.previousActiveElement)) {
      this.previousActiveElement.focus({preventScroll: true})
    }
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
  },

  _lockBodyScroll() {
    const body = document.body
    const root = document.documentElement
    const nextCount = parseInt(body.dataset.modalLockCount || "0", 10) + 1
    body.dataset.modalLockCount = String(nextCount)
    body.dataset.modalScrollLocked = ""
    root.dataset.modalScrollLocked = ""
    body.classList.add("overflow-hidden")
    root.classList.add("overflow-hidden")
  },

  _unlockBodyScroll() {
    const body = document.body
    const root = document.documentElement
    const nextCount = Math.max(0, parseInt(body.dataset.modalLockCount || "1", 10) - 1)

    if (nextCount === 0) {
      delete body.dataset.modalLockCount
      delete body.dataset.modalScrollLocked
      delete root.dataset.modalScrollLocked
      body.classList.remove("overflow-hidden")
      root.classList.remove("overflow-hidden")
    } else {
      body.dataset.modalLockCount = String(nextCount)
    }
  }
}

export default ModalDialog
