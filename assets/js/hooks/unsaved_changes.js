// Reusable navigation guard for forms with unsaved changes.
//
// Place `phx-hook="UnsavedChanges"` on a form (or any element with an `id`)
// and toggle `data-dirty="true"` from the server when there are unsaved
// edits. The hook also tracks `input`/`change` events on the host element
// so fields with `phx-debounce` (which delay the server-side dirty flag)
// still trigger the guard the moment the user types.
//
// Covers four navigation paths:
//   1. Tab close / reload / external URL — `beforeunload`.
//   2. In-app `<.link navigate>` / `<.link patch>` clicks — capture-phase
//      click handler on `document`.
//   3. Browser back / forward — module-level `popstate` listener that
//      runs before LiveView's (registered at import time, before
//      `liveSocket.connect()`).
//   4. Per-link opt-out via `data-unsaved-skip="true"`.

const CONFIRM_MESSAGE = "You have unsaved changes. Leave this page?"

// Active hook instances. Module-level so the popstate listener below can
// see them.
const guards = new Set()

function anyDirty() {
  for (const guard of guards) {
    if (guard._isDirty()) return true
  }
  return false
}

function firstDirtyGuard() {
  for (const guard of guards) {
    if (guard._isDirty()) return guard
  }
  return null
}

// Registered at module load time — before `liveSocket.connect()` runs in
// app.js — so this listener fires before LiveView's own popstate handler.
// That ordering lets us `stopImmediatePropagation()` to suppress LiveView's
// nav when the user chooses to stay.
window.addEventListener("popstate", (event) => {
  if (!anyDirty()) return

  if (window.confirm(CONFIRM_MESSAGE)) {
    // Confirmed leave — disable guards so we don't re-prompt for this
    // navigation, then let LiveView's popstate handler run.
    for (const guard of guards) guard._disable()
    return
  }

  // Stay — block LiveView from processing this popstate and push the URL
  // back to where we were.
  event.stopImmediatePropagation()

  const guard = firstDirtyGuard()
  if (guard) {
    window.history.pushState(guard._guardState, "", guard._guardUrl)
  }
})

const UnsavedChanges = {
  mounted() {
    this._serverDirty = false
    this._clientDirty = false
    this._guardUrl = window.location.href
    this._guardState = window.history.state
    guards.add(this)
    this._sync()

    this._onBeforeUnload = (event) => {
      if (!this._isDirty()) return
      event.preventDefault()
      // Legacy: older Firefox only shows the prompt when `returnValue` is set.
      event.returnValue = ""
    }

    this._onClick = (event) => {
      if (!this._isDirty()) return
      if (event.defaultPrevented) return
      if (event.button !== 0) return
      if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return

      const link = event.target.closest("a[href]")
      if (!link) return
      if (link.target && link.target !== "_self") return
      if (link.hasAttribute("download")) return
      if (link.dataset.unsavedSkip === "true") return

      const href = link.getAttribute("href")
      if (!href) return
      if (href.startsWith("#")) return

      let url
      try {
        url = new URL(link.href, window.location.href)
      } catch (_err) {
        return
      }

      // Same path + same query is a no-op anchor; let it through.
      if (
        url.origin === window.location.origin &&
        url.pathname === window.location.pathname &&
        url.search === window.location.search
      ) {
        return
      }

      if (window.confirm(CONFIRM_MESSAGE)) return

      event.preventDefault()
      event.stopImmediatePropagation()
    }

    // Form fields with `phx-debounce` defer the server-side dirty flag
    // until blur/timeout. Track dirty client-side too so the guard kicks
    // in the moment the user types.
    this._onInput = (event) => {
      if (this.el.contains(event.target)) {
        this._clientDirty = true
      }
    }

    window.addEventListener("beforeunload", this._onBeforeUnload)
    document.addEventListener("click", this._onClick, true)
    this.el.addEventListener("input", this._onInput)
    this.el.addEventListener("change", this._onInput)
  },

  updated() {
    this._sync()
    // Keep the guard URL/state current if the server `push_patch`-ed.
    this._guardUrl = window.location.href
    this._guardState = window.history.state
  },

  destroyed() {
    guards.delete(this)
    window.removeEventListener("beforeunload", this._onBeforeUnload)
    document.removeEventListener("click", this._onClick, true)
    this.el.removeEventListener("input", this._onInput)
    this.el.removeEventListener("change", this._onInput)
  },

  _sync() {
    this._serverDirty = this.el.dataset.dirty === "true"
  },

  _isDirty() {
    return this._serverDirty || this._clientDirty
  },

  _disable() {
    this._serverDirty = false
    this._clientDirty = false
  }
}

export default UnsavedChanges
