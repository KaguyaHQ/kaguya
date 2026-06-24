const ModalDialog = {
  mounted() {
    this.previousActiveElement = document.activeElement instanceof HTMLElement
      ? document.activeElement
      : null
    this._lockBodyScroll()

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

    this._onMouseDown = event => {
      if (event.target === this.el) this._requestClose()
    }

    this._onKeyDown = event => {
      if (event.key === "Escape") {
        event.preventDefault()
        this._requestClose()
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
    this.el.addEventListener("keydown", this._onKeyDown)

    requestAnimationFrame(() => {
      const initial = this.el.querySelector("[data-modal-initial-focus]")
      const focusTarget = initial || this._focusableElements()[0]
      if (focusTarget instanceof HTMLElement) focusTarget.focus({preventScroll: true})
    })
  },

  destroyed() {
    this.el.removeEventListener("mousedown", this._onMouseDown)
    this.el.removeEventListener("keydown", this._onKeyDown)
    this._unlockBodyScroll()

    if (this.previousActiveElement && document.contains(this.previousActiveElement)) {
      this.previousActiveElement.focus({preventScroll: true})
    }
  },

  _lockBodyScroll() {
    const body = document.body
    const nextCount = parseInt(body.dataset.modalLockCount || "0", 10) + 1
    body.dataset.modalLockCount = String(nextCount)
    body.classList.add("overflow-hidden")
  },

  _unlockBodyScroll() {
    const body = document.body
    const nextCount = Math.max(0, parseInt(body.dataset.modalLockCount || "1", 10) - 1)

    if (nextCount === 0) {
      delete body.dataset.modalLockCount
      body.classList.remove("overflow-hidden")
    } else {
      body.dataset.modalLockCount = String(nextCount)
    }
  }
}

export default ModalDialog
