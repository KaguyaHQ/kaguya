const CommentThread = {
  mounted() {
    this._resizeObserver = null
    this._measure = () => {
      const threadId = this.el.dataset.commentThreadId
      if (!threadId) return

      const trunk = this.el.querySelector(":scope > [data-comment-trunk]")
      const children = document.getElementById(`comment-thread-${threadId}-children`)
      const lastBranch = document.getElementById(`comment-thread-${threadId}-last-branch`)

      if (!trunk || !children || !lastBranch) return

      const outerRect = this.el.getBoundingClientRect()
      const branchRect = lastBranch.getBoundingClientRect()
      const buttonTop = parseFloat(getComputedStyle(trunk).top) || 26
      const isLg = window.matchMedia("(min-width: 1024px)").matches
      const junctionOffset = isLg ? 9 : 4
      const junctionY = branchRect.top - outerRect.top + junctionOffset

      trunk.style.height = `${Math.max(0, junctionY - buttonTop)}px`

      // Pin the +/- icon beside this comment's action row so it sits in the
      // same place at every depth, instead of midway down a long trunk.
      const actions = this.el.querySelector(`#comment-${threadId} [data-comment-actions]`)
      if (actions) {
        const actionsRect = actions.getBoundingClientRect()
        const toggleY = actionsRect.top + actionsRect.height / 2 - outerRect.top - buttonTop
        trunk.style.setProperty("--thread-toggle-y", `${Math.max(0, toggleY)}px`)
      } else {
        trunk.style.setProperty("--thread-toggle-y", "12px")
      }
    }

    this._bindObserver = () => {
      if (this._resizeObserver) this._resizeObserver.disconnect()

      const threadId = this.el.dataset.commentThreadId
      const children = threadId
        ? document.getElementById(`comment-thread-${threadId}-children`)
        : null

      this._resizeObserver = new ResizeObserver(() => this._scheduleMeasure())
      this._resizeObserver.observe(this.el)
      if (children) this._resizeObserver.observe(children)
    }

    this._scheduleMeasure = () => {
      cancelAnimationFrame(this._measureFrame)
      this._measureFrame = requestAnimationFrame(this._measure)
    }

    this._onResize = () => this._scheduleMeasure()
    this._bindObserver()
    this._scheduleMeasure()
    window.addEventListener("resize", this._onResize, {passive: true})
  },

  updated() {
    this._bindObserver()
    this._scheduleMeasure()
  },

  destroyed() {
    if (this._resizeObserver) this._resizeObserver.disconnect()
    cancelAnimationFrame(this._measureFrame)
    window.removeEventListener("resize", this._onResize)
  }
}

export default CommentThread
