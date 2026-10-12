// Cloudflare's SDK must stay hosted by Cloudflare. Load it once from this
// registered hook, including after LiveView navigation, rather than in layouts.
let sdkPromise

export function loadTurnstile() {
  if (sdkPromise) return sdkPromise
  if (window.turnstile) return Promise.resolve(window.turnstile)

  sdkPromise = new Promise((resolve, reject) => {
    const script = document.createElement("script")
    script.src = "https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit"
    script.async = true
    const timer = setTimeout(() => fail(), 10_000)
    const fail = () => {
      clearTimeout(timer)
      script.remove()
      sdkPromise = undefined
      reject(new Error("Security check unavailable"))
    }
    script.onerror = fail
    script.onload = () => {
      if (!window.turnstile) return fail()
      clearTimeout(timer)
      resolve(window.turnstile)
    }
    document.head.appendChild(script)
  })
  return sdkPromise
}

const Turnstile = {
  mounted() {
    this.form = this.el.closest("form")
    this.input = this.el.querySelector("input[name='cf-turnstile-response']")
    this.status = this.el.querySelector("[role='status']")
    this.retryButton = this.el.querySelector("[data-turnstile-retry]")
    this.onSubmit = event => {
      if (!this.input.value) {
        event.preventDefault()
        event.stopImmediatePropagation()
        this.setToken("", "Complete the security check before requesting a link.", true)
      } else {
        this.form.querySelectorAll("button[type='submit']").forEach(button => {
          button.disabled = true
        })
      }
    }
    this.onRetry = () => this.renderWidget()
    this.form.addEventListener("submit", this.onSubmit, {capture: true})
    this.retryButton.addEventListener("click", this.onRetry)
    this.renderWidget()
  },

  async renderWidget() {
    if (this.loading || this.isDestroyed) return
    this.loading = true
    this.setToken("", "Loading security check…")
    try {
      if (!this.el.dataset.siteKey) throw new Error("Security check unavailable")
      const sdk = await loadTurnstile()
      if (this.isDestroyed) return
      if (this.widgetId !== undefined) sdk.remove(this.widgetId)
      this.widgetId = sdk.render(this.el.querySelector("[data-turnstile-container]"), {
        sitekey: this.el.dataset.siteKey,
        action: this.el.dataset.action,
        theme: "auto",
        size: "flexible",
        "response-field": false,
        callback: token => this.setToken(token, "Security check complete."),
        "expired-callback": () => this.setToken("", "Security check expired. Please retry.", true),
        "timeout-callback": () => this.setToken("", "Security check timed out. Please retry.", true),
        "error-callback": () => {
          this.setToken("", "Security check unavailable. Please retry.", true)
          return true
        }
      })
    } catch {
      this.setToken("", "Security check unavailable. Please retry.", true)
    } finally {
      this.loading = false
    }
  },

  setToken(token, message, retry = false) {
    if (this.isDestroyed) return
    this.input.value = token
    this.el.dataset.verified = token ? "true" : "false"
    this.status.textContent = message
    this.retryButton.hidden = !retry
    this.syncButtons()
  },

  syncButtons() {
    this.form.querySelectorAll("button[type='submit']").forEach(button => {
      button.disabled = !this.input.value || button.dataset.cooldown === "true"
    })
  },

  updated() {
    this.syncButtons()
  },

  destroyed() {
    this.isDestroyed = true
    // LiveView also destroys hooks before a native form navigation. Preserve
    // the hidden response until the browser has serialized the submitted form.
    this.form.removeEventListener("submit", this.onSubmit, {capture: true})
    this.retryButton.removeEventListener("click", this.onRetry)
    if (this.widgetId !== undefined) window.turnstile?.remove(this.widgetId)
  }
}

export default Turnstile
