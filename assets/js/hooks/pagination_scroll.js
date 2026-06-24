// Scrolls back to the top (or to a specific anchor) when the user clicks
// a page link inside the shared `<.pagination>` component, so paginated views
// (lists, browse, reviews, etc.) start fresh at the top after a page change.
//
// Honors an optional `data-scroll-target-id` attribute on the host
// element — when set, scrolls to that element instead of the window top.

const PaginationScroll = {
  mounted() {
    this._onClick = event => {
      const link = event.target.closest("a[href]")
      if (!link || !this.el.contains(link)) return
      // Modified clicks (cmd/ctrl/shift/middle-click) open in a new
      // tab/window — don't scroll the current one.
      if (event.button !== 0) return
      if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return

      const targetId = this.el.dataset.scrollTargetId
      if (targetId) {
        const target = document.getElementById(targetId)
        if (target) {
          target.scrollIntoView({behavior: "auto"})
          return
        }
      }

      window.scrollTo({top: 0, behavior: "auto"})
    }

    this.el.addEventListener("click", this._onClick)
  },

  destroyed() {
    this.el.removeEventListener("click", this._onClick)
  }
}

export default PaginationScroll
