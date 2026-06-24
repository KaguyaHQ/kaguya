const NotificationsReadTracker = {
  mounted() {
    this.sent = false
    this.hadUnread = this.el.dataset.hadUnread === "true"
    this.onPageLoadingStart = () => this.markRead()
    this.onBeforeUnload = () => this.markRead()
    window.addEventListener("phx:page-loading-start", this.onPageLoadingStart)
    window.addEventListener("beforeunload", this.onBeforeUnload)
  },

  updated() {
    if (this.el.dataset.hadUnread === "true") this.hadUnread = true
  },

  destroyed() {
    this.markRead()
    window.removeEventListener("phx:page-loading-start", this.onPageLoadingStart)
    window.removeEventListener("beforeunload", this.onBeforeUnload)
  },

  markRead() {
    if (!this.hadUnread || this.sent) return
    this.sent = true
    this.pushEvent("mark-all-notifications-read", {passive: true})
  }
}

export default NotificationsReadTracker
