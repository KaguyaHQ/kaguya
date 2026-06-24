// Pops the reading-status glyph when a status becomes active in the VN
// sidebar's status segments. The active state is owned by the server (optimistic
// render in StatusActions), so the icon swap (outline -> fill) and color change
// arrive on a LiveView patch. morphdom reverts any class we add before the
// patch, so we drive the animation from `updated()` — the same pattern the
// LikeButton hook uses — re-applying the pop after the active glyph has settled.
//
// We only pop in response to a click on a segment, never on the initial
// viewer-bundle hydration (which also flips active from "" to a status, but
// should stay quiet).
const StatusSegments = {
  mounted() {
    this._active = this.el.dataset.active || ""
    this._pending = false
    this._onClick = (event) => {
      if (!event.target.closest("[data-status-segment]")) return
      // Arm the pop and wait for the server patch. We can't time-box this: the
      // patch round-trip (DB write + cache bust + viewer-bundle refetch) is
      // fast locally but routinely exceeds a fixed window on production, which
      // would silently swallow the animation. `data-active` only ever changes
      // as a result of the viewer's own click, so keeping the flag armed until
      // the active status actually changes is safe — an unrelated patch never
      // moves it, and a no-op re-click simply re-arms on the next real change.
      this._pending = true
    }
    this.el.addEventListener("click", this._onClick)
  },

  updated() {
    const next = this.el.dataset.active || ""
    if (next !== this._active) {
      if (this._pending && next) this._pop(next)
      this._pending = false
      this._active = next
    }
  },

  destroyed() {
    this.el.removeEventListener("click", this._onClick)
  },

  _pop(value) {
    const segment = this.el.querySelector(`[data-status-segment="${value}"]`)
    const icon = segment && segment.querySelector("[data-status-icon]")
    if (!icon) return
    icon.classList.remove("kaguya-status-pop")
    void icon.offsetWidth // restart the animation
    icon.classList.add("kaguya-status-pop")
  }
}

export default StatusSegments
