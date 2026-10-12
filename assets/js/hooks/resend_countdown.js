// The server supplies the remaining recipient cooldown, including after the
// first signup email, a refresh, or a request made from another browser.
const ResendCountdown = {
  mounted() {
    this.button = this.el
    this.label = this.el.textContent.trim()
    this.form = this.el.closest("form")
    this.cooldownMs = this.el.dataset.cooldownMs
    this.startCountdown()
  },

  startCountdown() {
    if (this.interval) clearInterval(this.interval)
    const remainingMs = Math.max(0, Number(this.el.dataset.cooldownMs) || 0)
    this.until = Date.now() + remainingMs
    this.tick()
    if (remainingMs > 0) this.interval = setInterval(() => this.tick(), 1000)
  },

  tick() {
    const seconds = Math.ceil((this.until - Date.now()) / 1000)
    if (seconds > 0) {
      this.button.disabled = true
      this.button.dataset.cooldown = "true"
      this.button.textContent = `Resend available in ${seconds} seconds`
    } else {
      this.restore()
    }
  },

  restore() {
    const widget = this.form?.querySelector("[data-turnstile-widget]")
    this.button.disabled = Boolean(widget && widget.dataset.verified !== "true")
    this.button.textContent = this.label
    delete this.button.dataset.cooldown
    if (this.interval) clearInterval(this.interval)
    this.interval = null
  },

  updated() {
    if (this.cooldownMs !== this.el.dataset.cooldownMs) {
      this.cooldownMs = this.el.dataset.cooldownMs
      this.startCountdown()
    }
  },

  destroyed() {
    if (this.interval) clearInterval(this.interval)
  }
}

export default ResendCountdown
