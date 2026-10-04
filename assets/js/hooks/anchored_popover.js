// Positions native popovers and supplies disclosure behavior on browsers
// without the Popover API (or its :popover-open selector).
//
// The panel is rendered inline in the LiveView template; native popovers are
// promoted to the top layer. This hook NEVER moves the node out of the DOM. It:
//   * positions the panel relative to its trigger (anchor) on open, with
//     flip/shift to stay in the viewport,
//   * repositions on scroll/resize while open,
//   * syncs `aria-expanded`/`data-state` on the trigger,
//   * dismisses the panel when a `[data-menu-dismiss]` item is clicked.
//
// Native light-dismiss and focus return come from the Popover API. The fallback
// handles these itself while leaving the panel in LiveView's DOM.

function placePanel(panel, anchor, opts) {
  const {placement, align, sideOffset, alignOffset} = opts
  const a = anchor.getBoundingClientRect()
  const w = panel.offsetWidth
  const h = panel.offsetHeight
  const vw = window.innerWidth
  const vh = window.innerHeight

  const base = (side) => {
    let x = 0
    let y = 0
    switch (side) {
      case "top":
        y = a.top - h - sideOffset
        break
      case "bottom":
        y = a.bottom + sideOffset
        break
      case "left":
        x = a.left - w - sideOffset
        y = a.top
        break
      case "right":
        x = a.right + sideOffset
        y = a.top
        break
    }
    const horizontal = side === "top" || side === "bottom"
    switch (align) {
      case "start":
        if (horizontal) x = a.left + alignOffset
        else y = a.top + alignOffset
        break
      case "center":
        if (horizontal) x = a.left + a.width / 2 - w / 2 + alignOffset
        else y = a.top + a.height / 2 - h / 2 + alignOffset
        break
      case "end":
        if (horizontal) x = a.right - w + alignOffset
        else y = a.bottom - h + alignOffset
        break
    }
    return {x, y}
  }

  // Flip to the opposite side if the preferred side overflows.
  let side = placement
  let {x, y} = base(side)
  const overflows = (s, px, py) => {
    if (s === "top") return py < 0
    if (s === "bottom") return py + h > vh
    if (s === "left") return px < 0
    if (s === "right") return px + w > vw
    return false
  }
  const opposite = {top: "bottom", bottom: "top", left: "right", right: "left"}
  if (overflows(side, x, y)) {
    const flipped = opposite[side]
    const alt = base(flipped)
    if (!overflows(flipped, alt.x, alt.y)) {
      side = flipped
      x = alt.x
      y = alt.y
    }
  }

  // Shift along the cross axis to stay in the viewport.
  x = Math.max(8, Math.min(x, vw - w - 8))
  y = Math.max(8, Math.min(y, vh - h - 8))

  panel.style.left = `${x}px`
  panel.style.top = `${y}px`
  panel.dataset.side = side
}

function supportsNativePopover(panel) {
  if (typeof panel.showPopover !== "function" || typeof panel.hidePopover !== "function") return false
  try {
    panel.matches(":popover-open")
    return true
  } catch {
    return false
  }
}

const AnchoredPopover = {
  mounted() {
    this.anchor = document.getElementById(this.el.dataset.anchor)
    this._readOptions()
    this.fallback = !supportsNativePopover(this.el)
    this.fallbackOpen = false

    this._isOpen = () => this.fallback ? this.fallbackOpen : this.el.matches(":popover-open")
    this._emitFallbackToggle = (type, newState) => {
      const event = new Event(type)
      event.newState = newState
      this.el.dispatchEvent(event)
    }
    this._show = () => {
      if (this._isOpen()) return
      if (this.fallback) {
        this._emitFallbackToggle("beforetoggle", "open")
        this.fallbackOpen = true
        this._syncState()
        this._emitFallbackToggle("toggle", "open")
      } else {
        this.el.showPopover()
      }
    }
    this._hide = (restoreFocus = false) => {
      if (!this._isOpen()) return
      if (this.fallback) {
        this._emitFallbackToggle("beforetoggle", "closed")
        this.fallbackOpen = false
        this._syncState()
        this._emitFallbackToggle("toggle", "closed")
        if (restoreFocus) this.anchor?.focus()
      } else {
        this.el.hidePopover()
      }
    }

    this._reposition = () => {
      if (!this.anchor || !this._isOpen()) return
      if (this.opts.matchWidth) this.el.style.width = `${this.anchor.offsetWidth}px`
      placePanel(this.el, this.anchor, this.opts)
    }
    this.resizeObserver = new ResizeObserver(this._reposition)

    this._syncState = () => {
      const open = this._isOpen()
      if (this.fallback) this.el.style.display = open ? "block" : "none"
      this.el.dataset.state = open ? "open" : "closed"
      if (this.anchor) {
        this.anchor.setAttribute("aria-expanded", open ? "true" : "false")
        this.anchor.dataset.state = open ? "open" : "closed"
      }
      if (open && this.anchor) {
        this._reposition()
        this.resizeObserver.observe(this.el)
        this.resizeObserver.observe(this.anchor)
        // Reveal only after positioning — the panel renders visibility:hidden
        // so the pre-placement paint at the default (top-left) spot never shows.
        this.el.style.visibility = "visible"
        window.addEventListener("scroll", this._reposition, true)
        window.addEventListener("resize", this._reposition)
      } else {
        this.resizeObserver.disconnect()
        if (this.opts.matchWidth) this.el.style.width = ""
        this.el.style.visibility = "hidden"
        window.removeEventListener("scroll", this._reposition, true)
        window.removeEventListener("resize", this._reposition)
      }
    }
    this._onToggle = () => this._syncState()
    this._onTriggerClick = () => this._isOpen() ? this._hide() : this._show()
    this._onDocumentClick = (event) => {
      if (!this.el.contains(event.target) && !this.anchor?.contains(event.target)) this._hide()
    }
    this._onKeydown = (event) => {
      if (event.key === "Escape" && this._isOpen()) {
        event.preventDefault()
        this._hide(true)
      }
    }
    this._onRequestedShow = () => this._show()
    this._onRequestedHide = () => this._hide()

    this._onClick = (event) => {
      const item = event.target.closest("[data-menu-dismiss]")
      if (item && !item.matches(":disabled, [aria-disabled=true]") && this._isOpen()) {
        this._hide(true)
      }
    }

    this.el.addEventListener("toggle", this._onToggle)
    this.el.addEventListener("click", this._onClick)
    this.el.addEventListener("anchored-popover:show", this._onRequestedShow)
    this.el.addEventListener("anchored-popover:hide", this._onRequestedHide)
    if (this.fallback) {
      this._configureFallback()
      document.addEventListener("click", this._onDocumentClick)
      document.addEventListener("keydown", this._onKeydown)
    }
    this._syncState()
  },

  updated() {
    // LiveView patches the menu content and can restore its initial hidden
    // style without changing the browser's open state (or firing toggle).
    this.resizeObserver.disconnect()
    if (this.fallback) this._unbindTrigger()
    this.anchor = document.getElementById(this.el.dataset.anchor)
    this._readOptions()
    if (this.fallback) this._configureFallback()
    if (!this.opts.matchWidth) this.el.style.width = ""
    this._syncState()
  },

  _configureFallback() {
    // LiveView can restore these attributes during a patch. Remove the native
    // trigger behavior so it cannot toggle alongside the fallback handler.
    this.anchor?.removeAttribute("popovertarget")
    this.el.removeAttribute("popover")
    this.el.dataset.popoverFallback = ""
    this.el.style.position = "fixed"
    this.el.style.inset = "auto"
    this.el.style.margin = "0"
    this.el.style.zIndex = "9999"
    if (this.el.getAttribute("role") !== "tooltip") {
      this.anchor?.addEventListener("click", this._onTriggerClick)
    }
  },

  _unbindTrigger() {
    this.anchor?.removeEventListener("click", this._onTriggerClick)
  },

  _readOptions() {
    this.opts = {
      placement: this.el.dataset.placement || "bottom",
      align: this.el.dataset.align || "start",
      sideOffset: parseInt(this.el.dataset.sideOffset || "8", 10),
      alignOffset: parseInt(this.el.dataset.alignOffset || "0", 10),
      matchWidth: this.el.dataset.matchWidth === "true",
    }
  },

  destroyed() {
    this.resizeObserver.disconnect()
    if (this.fallback) {
      this._unbindTrigger()
      document.removeEventListener("click", this._onDocumentClick)
      document.removeEventListener("keydown", this._onKeydown)
    }
    this.el.removeEventListener("toggle", this._onToggle)
    this.el.removeEventListener("click", this._onClick)
    this.el.removeEventListener("anchored-popover:show", this._onRequestedShow)
    this.el.removeEventListener("anchored-popover:hide", this._onRequestedHide)
    window.removeEventListener("scroll", this._reposition, true)
    window.removeEventListener("resize", this._reposition)
  },
}

export default AnchoredPopover
