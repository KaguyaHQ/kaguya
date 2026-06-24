// Persists the "spoiler revealed" state for a review-level spoiler gate
// (the `<details>` wrapping a review body when `is_spoiler` is true). Mirrors
// the Next.js `useSpoilerRevealed` hook so the same localStorage key
// (`spoiler:{review-id}`) controls both apps — a user who reveals a spoiler
// in one surface won't see the gate again in the other.
//
// Usage:
//   <details
//     id={"review-spoiler-#{@review.id}"}
//     phx-hook="SpoilerScope"
//     data-spoiler-scope={"review:#{@review.id}"}
//   >...</details>
//
// The scope id is opaque — any `{namespace}:{id}` string works; we only
// require it to match the Next.js convention to keep storage compatible.

const STORAGE_PREFIX = "spoiler:"

const SpoilerScope = {
  mounted() {
    this._scope = this.el.dataset.spoilerScope
    if (!this._scope) return

    // Extract the bare id — `review:abc123` → `abc123`. Falls back to the
    // full scope if there's no `:` so callers can use either form.
    const bareId = this._scope.includes(":")
      ? this._scope.slice(this._scope.indexOf(":") + 1)
      : this._scope
    this._key = `${STORAGE_PREFIX}${bareId}`

    // Hydrate from storage. We can only set `open` on `<details>`; for any
    // other tag the caller can still listen to data-spoiler-revealed if they
    // want bespoke styling, but we won't auto-style anything here.
    if (this._isRevealed()) {
      if (this.el.tagName === "DETAILS") this.el.open = true
      this.el.dataset.spoilerRevealed = "1"
    }

    this._onToggle = () => {
      if (this.el.tagName === "DETAILS" && this.el.open) this._persist()
    }

    this._onClick = event => {
      // Inline `||spoiler||` spans inside the scope: persist when revealed so
      // they stay open across navigation, same as the review-level gate.
      const span = event.target.closest?.("[data-spoiler]")
      if (span && this.el.contains(span) && span.classList.contains("revealed")) {
        this._persist()
      }
    }

    this.el.addEventListener("toggle", this._onToggle)
    this.el.addEventListener("click", this._onClick)
  },

  destroyed() {
    if (this._onToggle) this.el.removeEventListener("toggle", this._onToggle)
    if (this._onClick) this.el.removeEventListener("click", this._onClick)
  },

  _isRevealed() {
    try {
      return localStorage.getItem(this._key) === "1"
    } catch {
      return false
    }
  },

  _persist() {
    try {
      localStorage.setItem(this._key, "1")
      this.el.dataset.spoilerRevealed = "1"
    } catch {
      // Storage full / disabled — best-effort, fail silently.
    }
  }
}

export default SpoilerScope
