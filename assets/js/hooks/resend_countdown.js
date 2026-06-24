// Disables the signup-confirmation resend button for 30s after submit, with
// a live countdown ("Resend in 30s"). Cooldown timestamp is stored in
// localStorage so it survives the redirect-back the form submission triggers.
const STORAGE_KEY = "kaguya:resend-cooldown-until"
const COOLDOWN_MS = 30_000

const readUntil = () => {
  const raw = window.localStorage.getItem(STORAGE_KEY)
  const parsed = raw ? parseInt(raw, 10) : 0
  return Number.isFinite(parsed) ? parsed : 0
}

const writeUntil = until => {
  if (until > Date.now()) {
    window.localStorage.setItem(STORAGE_KEY, String(until))
  } else {
    window.localStorage.removeItem(STORAGE_KEY)
  }
}

const ResendCountdown = {
  mounted() {
    this.button = this.el
    this.label = this.el.textContent.trim()
    this.form = this.el.closest("form")

    this.onSubmit = () => {
      writeUntil(Date.now() + COOLDOWN_MS)
    }

    this.tick = () => {
      const until = readUntil()
      const remainingMs = until - Date.now()

      if (remainingMs <= 0) {
        this.restore()
        return
      }

      const remainingSec = Math.ceil(remainingMs / 1000)
      this.button.disabled = true
      this.button.textContent = `Resend in ${remainingSec}s`
      this.button.dataset.cooldown = "true"
    }

    this.restore = () => {
      this.button.disabled = false
      this.button.textContent = this.label
      delete this.button.dataset.cooldown
      writeUntil(0)

      if (this.interval) {
        clearInterval(this.interval)
        this.interval = null
      }
    }

    this.form?.addEventListener("submit", this.onSubmit)

    // Resume an in-flight cooldown after the post-submit redirect re-renders the page.
    if (readUntil() > Date.now()) {
      this.tick()
      this.interval = setInterval(this.tick, 1000)
    }
  },

  destroyed() {
    this.form?.removeEventListener("submit", this.onSubmit)
    if (this.interval) clearInterval(this.interval)
  }
}

export default ResendCountdown
