// Client-toggled "read more" hook. See lib/kaguya_web/components/shared/read_more.ex.
//
// On mount, checks whether the collapsed content overflows. If it does,
// reveals the toggle button. Clicking the button swaps a single class —
// no LiveView round-trip.

const ReadMore = {
  mounted() {
    this._setup()
  },

  updated() {
    // If LiveView swaps the inner content (e.g. description streams in
    // after mount), re-evaluate overflow without losing the user's
    // current expanded/collapsed state.
    this._setup({preserveState: true})
  },

  destroyed() {
    if (this._onClick && this._button) {
      this._button.removeEventListener("click", this._onClick)
    }
    if (this._onClick && this._collapsed) {
      this.el.removeEventListener("click", this._onClick)
    }
  },

  _setup({preserveState = false} = {}) {
    // Responsive variant — two collapsed nodes (mobile + desktop), each
    // hidden at the opposite breakpoint by Tailwind classes. We treat the
    // pair as one collapsed slot for state purposes; the breakpoint swap
    // is pure CSS and stays orthogonal to expand/collapse.
    const collapsedMobile = this.el.querySelector("[data-readmore-collapsed-mobile]")
    const collapsedDesktop = this.el.querySelector("[data-readmore-collapsed-desktop]")
    const collapsed =
      this.el.querySelector("[data-readmore-collapsed]") ||
      collapsedMobile ||
      collapsedDesktop
    const expandedContent = this.el.querySelector("[data-readmore-expanded]")
    if (collapsed && expandedContent) {
      this._setupInline({
        preserveState,
        collapsed,
        collapsedMobile,
        collapsedDesktop,
        expandedContent
      })
      return
    }

    const content = this.el.querySelector("[data-readmore-content]")
    const button = this.el.querySelector("[data-readmore-toggle]")
    if (!content || !button) return

    this._content = content
    this._button = button

    const expanded = preserveState && this.el.dataset.expanded === "true"
    this._apply(expanded)

    // Defer overflow measurement to the next frame so fonts/images settle.
    requestAnimationFrame(() => {
      const overflows = content.scrollHeight > content.clientHeight + 2
      if (overflows) {
        button.classList.remove("hidden")
      } else {
        button.classList.add("hidden")
        // No overflow → render the content uncollapsed so the line-clamp
        // doesn't ever clip late-loading content (e.g. emoji fallbacks).
        this._apply(true)
      }
    })

    if (this._onClick) {
      button.removeEventListener("click", this._onClick)
    }
    this._onClick = e => {
      e.preventDefault()
      const isExpanded = this.el.dataset.expanded === "true"
      this._apply(!isExpanded)
    }
    button.addEventListener("click", this._onClick)
  },

  _setupInline({
    preserveState = false,
    collapsed,
    collapsedMobile = null,
    collapsedDesktop = null,
    expandedContent
  }) {
    this._collapsed = collapsed
    this._collapsedMobile = collapsedMobile
    this._collapsedDesktop = collapsedDesktop
    this._expandedContent = expandedContent

    const expanded = preserveState && this.el.dataset.expanded === "true"
    this._applyInline(expanded)

    if (this._onClick) {
      this.el.removeEventListener("click", this._onClick)
    }

    this._onClick = e => {
      const toggle = e.target.closest?.("[data-readmore-expand], [data-readmore-collapse]")
      if (!toggle || !this.el.contains(toggle)) return
      e.preventDefault()
      this._applyInline(toggle.hasAttribute("data-readmore-expand"))
    }

    this.el.addEventListener("click", this._onClick)
  },

  _apply(expanded) {
    if (!this._content || !this._button) return
    this.el.dataset.expanded = expanded ? "true" : "false"
    this._content.classList.toggle("readmore-collapsed", !expanded)
    const label = expanded
      ? this._button.dataset.collapseLabel
      : this._button.dataset.expandLabel
    if (label) this._button.textContent = label
  },

  _applyInline(expanded) {
    if (!this._collapsed || !this._expandedContent) return
    this.el.dataset.expanded = expanded ? "true" : "false"
    this._collapsed.classList.toggle("hidden", expanded)
    this._expandedContent.classList.toggle("hidden", !expanded)
  }
}

export default ReadMore
