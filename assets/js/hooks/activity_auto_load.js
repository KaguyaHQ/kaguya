import {booleanValue} from "../lib/dom"

const ActivityAutoLoad = {
  mounted() {
    this.pending = false
    this.visible = false
    this.observer = new IntersectionObserver(entries => {
      const entry = entries[0]
      this.visible = !!entry?.isIntersecting
      this.maybePush()
    }, {rootMargin: "160px 0px"})
    this.observer.observe(this.el)
    this.render()
  },

  updated() {
    this.pending = booleanValue(this.el.dataset.loadingMore)
    this.render()
    this.maybePush()
  },

  destroyed() {
    this.observer?.disconnect()
  },

  maybePush() {
    if (!this.visible || this.pending) return
    this.pending = true
    this.render()
    this.pushEvent("load_more_activity", {})
  },

  render() {
    this.el.textContent = "Loading more activity"
  }
}

export default ActivityAutoLoad
