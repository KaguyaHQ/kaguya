// Native <dialog> modal driver for the `<.dialog>` primitive
// (lib/kaguya_web/components/ui/dialog.ex).
//
// The element is a real <dialog>, server-gated by the caller's `:if`. On mount
// the hook calls `.showModal()` — the browser provides the top layer, focus
// trap, Esc-to-cancel, `::backdrop`, and inert background for free. The hook
// only adds backdrop-click dismissal and forwards native close/cancel to the
// server so it can flip its open assign.
const Dialog = {
  mounted() {
    this._closing = false

    this._onCancel = (event) => {
      // Let our close handler own the server round-trip so Esc and the close
      // button take the same path.
      event.preventDefault()
      this.el.close()
    }

    this._onClose = () => {
      if (this._closing) return
      this._closing = true
      const onClose = this.el.getAttribute("data-on-close")
      if (onClose) this.liveSocket.execJS(this.el, onClose)
    }

    // Native <dialog> doesn't dismiss on backdrop click; clicks on the backdrop
    // land on the <dialog> element itself. Cancel/close buttons opt in with
    // `data-dialog-close`.
    this._onClick = (event) => {
      if (event.target.closest("[data-dialog-close]")) {
        this.el.close()
        return
      }
      if (event.target === this.el && this.el.dataset.dismissable !== "false") {
        this.el.close()
      }
    }

    this.el.addEventListener("cancel", this._onCancel)
    this.el.addEventListener("close", this._onClose)
    this.el.addEventListener("click", this._onClick)

    if (!this.el.open) {
      this._closing = false
      this.el.showModal()
    }
  },

  destroyed() {
    this.el.removeEventListener("cancel", this._onCancel)
    this.el.removeEventListener("close", this._onClose)
    this.el.removeEventListener("click", this._onClick)
  },
}

export default Dialog
