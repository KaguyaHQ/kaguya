// Positioning-only hook for the native Popover API panel rendered by the
// `<.menu>` primitive (lib/kaguya_web/components/ui/menu.ex).
//
// The panel is a real `popover` element rendered inline in the LiveView
// template; the browser promotes it to the top layer. This hook NEVER moves
// the node out of the DOM — it only:
//   * positions the panel relative to its trigger (anchor) on open, with
//     flip/shift to stay in the viewport,
//   * repositions on scroll/resize while open,
//   * syncs `aria-expanded`/`data-state` on the trigger,
//   * dismisses the panel when a `[data-menu-dismiss]` item is clicked.
//
// Native light-dismiss (click-outside + Esc) and focus return to the trigger
// come for free from the Popover API.

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

const AnchoredPopover = {
  mounted() {
    this.anchor = document.getElementById(this.el.dataset.anchor)
    this.opts = {
      placement: this.el.dataset.placement || "bottom",
      align: this.el.dataset.align || "start",
      sideOffset: parseInt(this.el.dataset.sideOffset || "8", 10),
      alignOffset: parseInt(this.el.dataset.alignOffset || "0", 10),
      matchWidth: this.el.dataset.matchWidth === "true",
    }

    this._reposition = () => {
      if (this.el.matches(":popover-open")) placePanel(this.el, this.anchor, this.opts)
    }

    this._onToggle = (event) => {
      const open = event.newState === "open"
      if (this.anchor) {
        this.anchor.setAttribute("aria-expanded", open ? "true" : "false")
        this.anchor.dataset.state = open ? "open" : "closed"
      }
      if (open) {
        if (this.opts.matchWidth && this.anchor) {
          this.el.style.width = `${this.anchor.offsetWidth}px`
        }
        placePanel(this.el, this.anchor, this.opts)
        window.addEventListener("scroll", this._reposition, true)
        window.addEventListener("resize", this._reposition)
      } else {
        if (this.opts.matchWidth) this.el.style.width = ""
        window.removeEventListener("scroll", this._reposition, true)
        window.removeEventListener("resize", this._reposition)
      }
    }

    this._onClick = (event) => {
      if (event.target.closest("[data-menu-dismiss]")) this.el.hidePopover()
    }

    // The hook owns data-state on the trigger (the server template does NOT
    // render it) — otherwise a server patch while the menu is open would
    // revert data-state=open back to closed via morphdom.
    if (this.anchor) this.anchor.dataset.state = "closed"

    this.el.addEventListener("toggle", this._onToggle)
    this.el.addEventListener("click", this._onClick)
  },

  destroyed() {
    this.el.removeEventListener("toggle", this._onToggle)
    this.el.removeEventListener("click", this._onClick)
    window.removeEventListener("scroll", this._reposition, true)
    window.removeEventListener("resize", this._reposition)
  },
}

export default AnchoredPopover
